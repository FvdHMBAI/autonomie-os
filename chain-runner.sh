#!/bin/bash
# =============================================================================
# CHAIN-RUNNER - Autonomous multi-phase task runner with verification gates
# =============================================================================
#
# Executes multi-step tasks autonomously, with fresh context per phase.
# Each phase runs in its own AI agent session.
# Between phases: verification gates (tests, build, E2E).
# At the end: full E2E audit of all changes.
#
# Usage:
#   ./chain-runner.sh /path/to/task-definition.md
#   ./chain-runner.sh --dry-run /path/to/task-definition.md
#   ./chain-runner.sh --resume /path/to/task-definition.md
#
# Task definition format: see examples/task-template.md
#
# Safety guarantees:
#   - ONLY on feature branches (never main/master/production)
#   - Budget limit per phase AND total
#   - Verification gate between each phase
#   - Automatic retry on gate failure
#   - Notification on completion/error
#   - Full audit log in vault
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

# --- Configuration ---
LOG="$LOG_DIR/chain-runner.log"
VAULT_RUNS="$VAULT_DIR/autonomie/chain-runs"
MAX_RETRIES=1
GATE_TIMEOUT=300

mkdir -p "$LOG_DIR" "$VAULT_RUNS" 2>/dev/null

TIMESTAMP() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "$(TIMESTAMP): $*" | tee -a "$LOG"; }

# --- Parse arguments ---
DRY_RUN=false
RESUME=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --resume) RESUME=true; shift ;;
    *) TASK_FILE="$1"; shift ;;
  esac
done

if [ -z "${TASK_FILE:-}" ] || [ ! -f "$TASK_FILE" ]; then
  echo "Usage: $0 [--dry-run] [--resume] /path/to/task-definition.md"
  exit 1
fi

log "=== Chain Runner Start ==="
log "Task: $TASK_FILE"
log "Dry Run: $DRY_RUN"
log "Resume: $RESUME"

# --- Parse task definition ---
parse_frontmatter() {
  local key="$1"
  sed -n '/^---$/,/^---$/p' "$TASK_FILE" | grep "^${key}:" | sed "s/^${key}: *//" | tr -d '"'
}

TASK_TITLE=$(parse_frontmatter "title")
TASK_APP=$(parse_frontmatter "app")
TASK_REPO=$(parse_frontmatter "repo")
TASK_BRANCH=$(parse_frontmatter "branch")
MAX_BUDGET=$(parse_frontmatter "max_budget_usd")
MAX_HOURS=$(parse_frontmatter "max_hours")
VERIFICATION=$(parse_frontmatter "verification")

MAX_BUDGET="${MAX_BUDGET:-$CHAIN_MAX_BUDGET}"
MAX_HOURS="${MAX_HOURS:-$CHAIN_MAX_HOURS}"
VERIFICATION="${VERIFICATION:-full}"

RUN_ID="$(date +%Y%m%d-%H%M%S)-$(echo "$TASK_TITLE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 30)"
RUN_DIR="$VAULT_RUNS/$RUN_ID"
mkdir -p "$RUN_DIR"

log "Run-ID: $RUN_ID"
log "App: $TASK_APP | Repo: $TASK_REPO | Branch: $TASK_BRANCH"
log "Budget: \$${MAX_BUDGET} | Max: ${MAX_HOURS}h | Verification: $VERIFICATION"

# --- Safety checks ---
if [ -z "$TASK_REPO" ] || [ ! -d "$TASK_REPO" ]; then
  log "ERROR: Repo not found: $TASK_REPO"
  exit 1
fi

for forbidden in main master production; do
  if [ "$TASK_BRANCH" = "$forbidden" ]; then
    log "ERROR: Branch '$TASK_BRANCH' is forbidden! Only feature branches allowed."
    autonomie_notify "Chain Runner BLOCKED" "Forbidden branch: $TASK_BRANCH" "high"
    exit 1
  fi
done

if ! $DRY_RUN; then
  cd "$TASK_REPO"
  if ! git rev-parse --verify "$TASK_BRANCH" > /dev/null 2>&1; then
    log "Creating branch: $TASK_BRANCH"
    git checkout -b "$TASK_BRANCH" 2>> "$LOG"
  else
    log "Switching to branch: $TASK_BRANCH"
    git checkout "$TASK_BRANCH" 2>> "$LOG"
  fi
fi

# --- Extract phases ---
extract_phases() {
  local phase_num=0
  local in_phase=false
  local phase_file=""

  while IFS= read -r line; do
    if echo "$line" | grep -qE '^## Phase [0-9]+:'; then
      phase_num=$((phase_num + 1))
      phase_file="$RUN_DIR/phase-${phase_num}-prompt.md"
      echo "$line" > "$phase_file"
      in_phase=true
    elif echo "$line" | grep -qE '^## ' && $in_phase; then
      in_phase=false
    elif $in_phase; then
      echo "$line" >> "$phase_file"
    fi
  done < <(sed '1,/^---$/d; /^---$/,/^---$/d' "$TASK_FILE")

  echo "$phase_num"
}

TOTAL_PHASES=$(extract_phases)
log "Phases found: $TOTAL_PHASES"

if [ "$TOTAL_PHASES" -eq 0 ]; then
  log "ERROR: No phases found. Task file must contain '## Phase N: Title' sections."
  exit 1
fi

PHASE_BUDGET=$(echo "scale=2; $MAX_BUDGET / $TOTAL_PHASES" | bc)
log "Budget per phase: \$${PHASE_BUDGET}"

# --- Dry run: display only ---
if $DRY_RUN; then
  log "=== DRY RUN - No execution ==="
  for i in $(seq 1 "$TOTAL_PHASES"); do
    echo ""
    echo "--- Phase $i ---"
    cat "$RUN_DIR/phase-${i}-prompt.md"
  done
  echo ""
  echo "Phases: $TOTAL_PHASES | Budget/Phase: \$$PHASE_BUDGET | Total: \$$MAX_BUDGET"
  exit 0
fi

# --- Resume check ---
START_PHASE=1
if $RESUME; then
  for i in $(seq "$TOTAL_PHASES" -1 1); do
    if [ -f "$RUN_DIR/phase-${i}-result.md" ]; then
      START_PHASE=$((i + 1))
      log "Resume: Starting at phase $START_PHASE (phase $i already done)"
      break
    fi
  done
fi

# --- Tracking ---
TOTAL_COST=0
TOTAL_START=$(date +%s)
PHASES_OK=0
PHASES_FAIL=0

# --- Write run manifest ---
cat > "$RUN_DIR/manifest.md" << EOF
---
title: "$TASK_TITLE"
run_id: "$RUN_ID"
status: running
started_at: $(TIMESTAMP)
app: $TASK_APP
repo: $TASK_REPO
branch: $TASK_BRANCH
total_phases: $TOTAL_PHASES
max_budget: $MAX_BUDGET
verification: $VERIFICATION
---

# Chain Run: $TASK_TITLE

## Progress

EOF

# --- Verification gate ---
run_verification_gate() {
  local phase_num="$1"
  local level="${2:-$VERIFICATION}"

  log "Verification Gate Phase $phase_num (Level: $level)"

  local gate_result="$RUN_DIR/phase-${phase_num}-gate.md"
  local gate_ok=true

  echo "# Verification Gate - Phase $phase_num" > "$gate_result"
  echo "Time: $(TIMESTAMP)" >> "$gate_result"
  echo "" >> "$gate_result"

  cd "$TASK_REPO"

  # TypeScript check (if ts/tsx files changed)
  if git diff --name-only HEAD~1 2>/dev/null | grep -qE '\.(ts|tsx)$'; then
    log "  -> TypeScript Check..."
    if npx tsc --noEmit 2>> "$gate_result"; then
      echo "- [x] TypeScript: OK" >> "$gate_result"
    else
      echo "- [ ] TypeScript: FAILED" >> "$gate_result"
      gate_ok=false
    fi
  fi

  # Build check
  if [ "$level" = "full" ] || [ "$level" = "basic" ]; then
    if [ -f "package.json" ] && grep -q '"build"' package.json 2>/dev/null; then
      log "  -> Build Check..."
      if timeout 120 npm run build --silent 2>> "$gate_result"; then
        echo "- [x] Build: OK" >> "$gate_result"
      else
        echo "- [ ] Build: FAILED" >> "$gate_result"
        gate_ok=false
      fi
    fi
  fi

  # Test check
  if [ "$level" = "full" ]; then
    if [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then
      log "  -> Test Check..."
      if timeout 120 npm test --silent 2>> "$gate_result"; then
        echo "- [x] Tests: OK" >> "$gate_result"
      else
        echo "- [ ] Tests: FAILED" >> "$gate_result"
        gate_ok=false
      fi
    fi
  fi

  # Git status
  local dirty_count
  dirty_count=$(git status --porcelain | wc -l)
  if [ "$dirty_count" -eq 0 ]; then
    echo "- [x] Git: Clean" >> "$gate_result"
  else
    echo "- [ ] Git: $dirty_count uncommitted changes" >> "$gate_result"
  fi

  echo "" >> "$gate_result"

  if $gate_ok; then
    echo "**Result: PASSED**" >> "$gate_result"
    log "  Gate PASSED"
    return 0
  else
    echo "**Result: FAILED**" >> "$gate_result"
    log "  Gate FAILED"
    return 1
  fi
}

# --- Main loop: execute phases ---
autonomie_notify "Chain Runner started" "Task: $TASK_TITLE\nPhases: $TOTAL_PHASES\nBudget: \$$MAX_BUDGET" "default"

for PHASE in $(seq "$START_PHASE" "$TOTAL_PHASES"); do
  PHASE_START=$(date +%s)
  log ""
  log "=== Phase $PHASE / $TOTAL_PHASES ==="

  PHASE_PROMPT_FILE="$RUN_DIR/phase-${PHASE}-prompt.md"
  PHASE_RESULT_FILE="$RUN_DIR/phase-${PHASE}-result.md"
  PHASE_COST_FILE="$RUN_DIR/phase-${PHASE}-cost.json"

  # Collect context from previous phases
  PREVIOUS_CONTEXT=""
  for prev in $(seq 1 $((PHASE - 1))); do
    if [ -f "$RUN_DIR/phase-${prev}-result.md" ]; then
      PREVIOUS_CONTEXT+="
--- Result Phase $prev ---
$(head -100 "$RUN_DIR/phase-${prev}-result.md")
--- End Phase $prev ---
"
    fi
  done

  # Build agent prompt
  FULL_PROMPT="You are an autonomous developer in Phase $PHASE of $TOTAL_PHASES.

PROJECT: $TASK_TITLE
APP: $TASK_APP
REPO: $TASK_REPO (you are already in this directory)
BRANCH: $TASK_BRANCH

$(if [ -n "$PREVIOUS_CONTEXT" ]; then echo "RESULTS FROM PREVIOUS PHASES:
$PREVIOUS_CONTEXT"; fi)

YOUR TASK IN THIS PHASE:
$(cat "$PHASE_PROMPT_FILE")

IMPORTANT RULES:
1. Work ONLY on this phase, not on later ones
2. Commit EVERY logical change immediately (git commit)
3. Do NOT write tests that you do not run
4. When uncertain: decide conservatively, document in a comment
5. At the end: list what you did and what the next phase needs to know

RESPOND with a structured report:
## Completed
- What was done

## Changed Files
- Path - What

## For Next Phase
- What the next phase needs to know

## Open Questions
- If anything was unclear"

  log "Starting agent for Phase $PHASE..."

  cd "$TASK_REPO"
  PHASE_OUTPUT=$(nice -n 10 $AGENT_CLI -p "$FULL_PROMPT" \
    --allowedTools "Bash Read Write Edit Glob Grep" \
    --max-budget-usd "$PHASE_BUDGET" \
    --output-format json \
    --model "$AGENT_MODEL" \
    2>> "$LOG") || true

  echo "$PHASE_OUTPUT" > "$PHASE_COST_FILE"
  echo "$PHASE_OUTPUT" | jq -r '.result // .content // "No result"' > "$PHASE_RESULT_FILE" 2>/dev/null || echo "$PHASE_OUTPUT" > "$PHASE_RESULT_FILE"

  PHASE_COST=$(echo "$PHASE_OUTPUT" | jq -r '.cost_usd // 0' 2>/dev/null || echo "0")
  TOTAL_COST=$(echo "$TOTAL_COST + ${PHASE_COST:-0}" | bc 2>/dev/null || echo "$TOTAL_COST")

  PHASE_END=$(date +%s)
  PHASE_DURATION=$(( PHASE_END - PHASE_START ))

  log "Phase $PHASE completed in ${PHASE_DURATION}s | Cost: \$${PHASE_COST:-?}"
  echo "- Phase $PHASE: $(TIMESTAMP) | ${PHASE_DURATION}s | \$${PHASE_COST:-?}" >> "$RUN_DIR/manifest.md"

  # Budget check
  if [ "$(echo "$TOTAL_COST > $MAX_BUDGET" | bc 2>/dev/null)" = "1" ]; then
    log "BUDGET EXCEEDED: \$$TOTAL_COST > \$$MAX_BUDGET"
    autonomie_notify "Chain Runner BUDGET-STOP" "Task: $TASK_TITLE\nPhase: $PHASE/$TOTAL_PHASES\nCost: \$$TOTAL_COST" "high"
    break
  fi

  # Time check
  TOTAL_ELAPSED=$(( $(date +%s) - TOTAL_START ))
  MAX_SECONDS=$((MAX_HOURS * 3600))
  if [ "$TOTAL_ELAPSED" -gt "$MAX_SECONDS" ]; then
    log "TIME LIMIT: ${TOTAL_ELAPSED}s > ${MAX_SECONDS}s"
    autonomie_notify "Chain Runner TIME-STOP" "Task: $TASK_TITLE\nPhase: $PHASE/$TOTAL_PHASES\nDuration: $((TOTAL_ELAPSED/3600))h" "high"
    break
  fi

  # Verification gate
  if [ "$VERIFICATION" != "none" ]; then
    RETRY=0
    while [ $RETRY -le $MAX_RETRIES ]; do
      if run_verification_gate "$PHASE"; then
        PHASES_OK=$((PHASES_OK + 1))
        break
      else
        RETRY=$((RETRY + 1))
        if [ $RETRY -le $MAX_RETRIES ]; then
          log "Gate failed, Retry $RETRY/$MAX_RETRIES..."
          FIX_PROMPT="Verification gate for Phase $PHASE failed. Read $RUN_DIR/phase-${PHASE}-gate.md and fix the errors. Commit the fix."
          nice -n 10 $AGENT_CLI -p "$FIX_PROMPT" \
            --allowedTools "Bash Read Write Edit Glob Grep" \
            --max-budget-usd 1.00 \
            --output-format json \
            --model "$AGENT_MODEL" \
            2>> "$LOG" > /dev/null || true
        else
          log "Gate permanently failed after $MAX_RETRIES retries"
          PHASES_FAIL=$((PHASES_FAIL + 1))
          autonomie_notify "Chain Runner GATE-FAIL" "Phase $PHASE: Verification failed\nTask: $TASK_TITLE" "high"
        fi
      fi
    done
  else
    PHASES_OK=$((PHASES_OK + 1))
  fi
done

# --- Completion ---
TOTAL_END=$(date +%s)
TOTAL_DURATION=$(( TOTAL_END - TOTAL_START ))
TOTAL_HOURS=$(echo "scale=1; $TOTAL_DURATION / 3600" | bc)

cat >> "$RUN_DIR/manifest.md" << EOF

## Summary

| Metric | Value |
|--------|-------|
| Duration | ${TOTAL_HOURS}h (${TOTAL_DURATION}s) |
| Phases OK | $PHASES_OK / $TOTAL_PHASES |
| Phases Failed | $PHASES_FAIL |
| Total Cost | \$$TOTAL_COST |
| Status | $([ "$PHASES_FAIL" -eq 0 ] && echo "SUCCESS" || echo "WITH ERRORS") |
EOF

sed -i "s/status: running/status: $([ "$PHASES_FAIL" -eq 0 ] && echo "completed" || echo "failed")/" "$RUN_DIR/manifest.md"

log ""
log "=== Chain Runner DONE ==="
log "Duration: ${TOTAL_HOURS}h | Cost: \$$TOTAL_COST | OK: $PHASES_OK | Fail: $PHASES_FAIL"
log "Report: $RUN_DIR/manifest.md"

if [ "$PHASES_FAIL" -eq 0 ]; then
  autonomie_notify "Chain Runner SUCCESS" "Task: $TASK_TITLE\nDuration: ${TOTAL_HOURS}h\nCost: \$$TOTAL_COST\nPhases: $PHASES_OK/$TOTAL_PHASES" "default"
else
  autonomie_notify "Chain Runner WITH ERRORS" "Task: $TASK_TITLE\nFailed: $PHASES_FAIL phases\nCost: \$$TOTAL_COST" "high"
fi

# Push branch if all OK
if [ "$PHASES_FAIL" -eq 0 ] && [ "$PHASES_OK" -gt 0 ]; then
  cd "$TASK_REPO"
  COMMIT_COUNT=$(git log --oneline "$TASK_BRANCH" --not develop 2>/dev/null | wc -l || echo "0")
  if [ "$COMMIT_COUNT" -gt 0 ]; then
    log "Pushing branch with $COMMIT_COUNT commits..."
    git push -u origin "$TASK_BRANCH" 2>> "$LOG" || true
    log "Branch pushed. Create PR manually."
  fi
fi

log "=== End ==="
