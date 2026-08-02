#!/bin/bash
# =============================================================================
# DREAMING.SH - Nightly Session Review + Self-Improvement
#
# Analyzes the day's sessions, detects patterns, writes playbooks,
# and updates skills/vault/memory automatically.
#
# Cron: 0 2 * * * /path/to/autonomie-os/modules/dreaming/dreaming.sh
# =============================================================================

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOG="$LOG_DIR/dreaming.log"
LOCKFILE="$LOCKFILE_DIR/dreaming.lock"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
TODAY=$(date "+%Y-%m-%d")
START_TIME=$(date +%s)

DREAMING_DIR="$VAULT_DIR/autonomie/dreaming"
PLAYBOOK_DIR="$VAULT_DIR/playbooks"

mkdir -p "$(dirname "$LOG")" "$DREAMING_DIR" "$PLAYBOOK_DIR"

# Log rotation
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 10000 ]; then
  tail -5000 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

# Mutex
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$TIMESTAMP: Dreaming already running, skipping" >> "$LOG"; exit 0; }

log() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG"; }

log "====== Dreaming Run started ======"

# Audit trail
RUN_ID_RAW=$(autonomie_db "
  INSERT INTO dreaming_runs (run_date, status) VALUES ('$TODAY', 'running') RETURNING id;
" 2>/dev/null || echo "0")
RUN_ID=$(echo "$RUN_ID_RAW" | grep -oP '^\d+' | head -1)
RUN_ID=${RUN_ID:-0}

# =============================================================================
# PHASE 1: COLLECT - Sessions + Learnings + Errors of the day
# =============================================================================

log "Phase 1: Collecting data"

SESSION_FILES_ALL=$(find "$SESSIONS_DIR" -maxdepth 2 \( -name "*${TODAY}*" -o -name "*$(date '+%Y-%m-%d' -d 'yesterday' 2>/dev/null || echo "$TODAY")*.md" \) -type f 2>/dev/null || true)
SESSION_FILES=$(echo "$SESSION_FILES_ALL" | head -10 || true)
SESSION_COUNT=$(echo "$SESSION_FILES" | grep -c "\.md$" 2>/dev/null || true)
SESSION_COUNT=${SESSION_COUNT:-0}
log "Sessions found: $SESSION_COUNT"

SESSION_DATA=""
for f in $SESSION_FILES; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  SUMMARY=$(grep -m1 "RESULT\|result\|Result\|## " "$f" 2>/dev/null | head -c 120 || echo "")
  SESSION_DATA="${SESSION_DATA}
- ${BASENAME}: ${SUMMARY}"
done

# Unapplied learnings (last 14 days, max 10)
UNAPPLIED_LEARNINGS=$(autonomie_db "
  SELECT id || '|' || source || '|' || LEFT(lesson, 60)
  FROM learning_items
  WHERE applied = false AND created_at > NOW() - INTERVAL '14 days'
  ORDER BY occurrence_count DESC
  LIMIT 10;
" || echo "")
LEARNING_COUNT=$(echo "$UNAPPLIED_LEARNINGS" | grep -c "|" 2>/dev/null || true)
LEARNING_COUNT=${LEARNING_COUNT:-0}
log "Unapplied Learnings: $LEARNING_COUNT"

# Recurring error patterns
RECURRING_ERRORS=$(autonomie_db "
  SELECT pattern_key || '|' || category || '|' || occurrence_count || '|' || LEFT(description, 80)
  FROM error_patterns
  WHERE resolved = false AND occurrence_count >= 2
  ORDER BY occurrence_count DESC
  LIMIT 10;
" || echo "")
ERROR_COUNT=$(echo "$RECURRING_ERRORS" | grep -c "|" 2>/dev/null || true)
ERROR_COUNT=${ERROR_COUNT:-0}
log "Recurring Error Patterns: $ERROR_COUNT"

# RAG misses (last 7 days)
RAG_MISSES=$(autonomie_db "
  SELECT LEFT(query, 100) || '|' || miss_count
  FROM rag_misses
  WHERE created_at > NOW() - INTERVAL '7 days'
  ORDER BY miss_count DESC
  LIMIT 15;
" || echo "")

# Git activity
GIT_SUMMARY=""
if [ -n "$MONITORED_REPOS" ]; then
  IFS=',' read -ra REPOS <<< "$MONITORED_REPOS"
  for REPO_PATH in "${REPOS[@]}"; do
    REPO_PATH=$(echo "$REPO_PATH" | xargs)
    [ -d "$REPO_PATH/.git" ] || continue
    REPO_NAME=$(basename "$REPO_PATH")
    COMMITS=$(cd "$REPO_PATH" && git log --since="yesterday" --oneline --no-merges 2>/dev/null | head -5)
    if [ -n "$COMMITS" ]; then
      GIT_SUMMARY="${GIT_SUMMARY}
### ${REPO_NAME}
${COMMITS}"
    fi
  done
fi

if [ "$SESSION_COUNT" = "0" ] && [ "$LEARNING_COUNT" = "0" ] && [ -z "$GIT_SUMMARY" ]; then
  log "No new sessions/learnings/commits. Analyzing existing data."
fi

# =============================================================================
# PHASE 2: LLM TRIAGE
# =============================================================================

log "Phase 2: LLM Triage"

TRIAGE_PROMPT="You are an experienced systems analyst for a software project with an AI agent framework (guards, skills, vault, automation).

Analyze this data and identify IMPROVEMENTS in these categories:

1. PLAYBOOK CANDIDATES: Recurring problems OR recurring manual steps that could be automated.
   Format: PLAYBOOK|symptom_or_workflow|diagnosis|fix_or_automation
2. LEARNINGS TO APPLY: Which unapplied learnings are concretely actionable? Small improvements count.
   Format: APPLY|learning_id|where_to_apply|how
3. PATTERN RECOGNITION: Recurring patterns, not just errors:
   - Workarounds that keep happening (-> guard or skill)
   - Manual steps that could be automated
   - Questions that keep coming up (-> documentation entry)
   - Similar fixes across different apps (-> multi-app rollout)
   Format: PATTERN|pattern_key|root_cause_or_observation|concrete_suggestion
4. KNOWLEDGE GAPS: RAG misses or topics from sessions that are not documented.
   Format: VAULTGAP|topic|suggested_path

Rules:
- Answer ONLY in these pipe-separated formats, one line per finding
- Max 30 lines, at least 5 if data is available
- No markdown, no prose, no explanations
- Do not search for perfect solutions. Small, incremental improvements are valuable.
- If NOTHING found: suggest at least 1 VAULTGAP or 1 PATTERN

=== SESSIONS ===
${SESSION_DATA:-No new sessions}

=== UNAPPLIED LEARNINGS (id|source|lesson) ===
${UNAPPLIED_LEARNINGS:-None}

=== RECURRING ERRORS (key|category|count|description) ===
${RECURRING_ERRORS:-None}

=== RAG MISSES (query|count) ===
${RAG_MISSES:-None}

=== GIT ACTIVITY ===
${GIT_SUMMARY:-No commits}"

TRIAGE_RESULT=$(autonomie_llm "$TRIAGE_PROMPT" 4096 0.3) || TRIAGE_RESULT=""

if [ -z "$(printf '%s' "$TRIAGE_RESULT" | tr -d '[:space:]')" ]; then
  log "ERROR: LLM triage returned no results"
  autonomie_notify "Dreaming aborted" "LLM triage failed" "high"
  exit 1
fi
log "Triage completed: $(echo "$TRIAGE_RESULT" | wc -l) lines"

# =============================================================================
# PHASE 3: PROCESS FINDINGS
# =============================================================================

log "Phase 3: Processing findings"

PLAYBOOKS_CREATED=0
LEARNINGS_APPLIED=0
PATTERNS_UPDATED=0
VAULT_GAPS_FILLED=0

# 3a. Create playbooks
while IFS='|' read -r type symptom diagnose fix; do
  [ "$type" != "PLAYBOOK" ] && continue
  [ -z "$symptom" ] && continue

  PKEY=$(echo "$symptom" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | head -c 40)
  PFILE="$PLAYBOOK_DIR/${PKEY}.md"

  if [ ! -f "$PFILE" ]; then
    cat > "$PFILE" << PBEOF
---
title: Playbook - ${symptom}
type: playbook
created: ${TODAY}
source: dreaming-run-${RUN_ID}
---

# Playbook: ${symptom}

## Symptom
${symptom}

## Diagnosis
${diagnose}

## Fix
${fix}

## History
- ${TODAY}: Created by Dreaming Run #${RUN_ID}
PBEOF
    PLAYBOOKS_CREATED=$((PLAYBOOKS_CREATED + 1))
    log "Playbook created: $PKEY"
  fi
done <<< "$TRIAGE_RESULT"

# 3b. Mark learnings as applied
while IFS='|' read -r type lid where how; do
  [ "$type" != "APPLY" ] && continue
  [ -z "$lid" ] && continue

  LID_CLEAN=$(echo "$lid" | tr -cd '0-9')
  [ -z "$LID_CLEAN" ] && continue

  autonomie_db_exec "
    UPDATE learning_items SET applied = true, applied_at = NOW(), updated_at = NOW()
    WHERE id = $LID_CLEAN AND applied = false;
  " "$LOG" && LEARNINGS_APPLIED=$((LEARNINGS_APPLIED + 1))
done <<< "$TRIAGE_RESULT"

# 3c. Update error patterns (add root cause)
while IFS='|' read -r type pkey root_cause suggestion; do
  [ "$type" != "PATTERN" ] && continue
  [ -z "$pkey" ] && continue

  PKEY_CLEAN=$(echo "$pkey" | sed "s/'/''/g" | xargs)
  ROOT_CLEAN=$(echo "$root_cause" | sed "s/'/''/g" | head -c 500)
  SUGGESTION_CLEAN=$(echo "$suggestion" | sed "s/'/''/g" | head -c 500)

  autonomie_db_exec "
    UPDATE error_patterns
    SET root_cause = COALESCE(root_cause, '') || E'\n[${TODAY}] ${ROOT_CLEAN}',
        mitigation = COALESCE(mitigation, '') || E'\n[${TODAY}] ${SUGGESTION_CLEAN}',
        updated_at = NOW()
    WHERE pattern_key = '${PKEY_CLEAN}';
  " "$LOG" && PATTERNS_UPDATED=$((PATTERNS_UPDATED + 1))
done <<< "$TRIAGE_RESULT"

# 3d. Document vault gaps (create stubs)
while IFS='|' read -r type topic path; do
  [ "$type" != "VAULTGAP" ] && continue
  [ -z "$topic" ] && continue

  STUB_PATH="${path:-known-issues/STUB_$(echo "$topic" | tr ' ' '_' | head -c 40).md}"
  FULL_PATH="$VAULT_DIR/$STUB_PATH"

  if [ ! -f "$FULL_PATH" ]; then
    mkdir -p "$(dirname "$FULL_PATH")"
    cat > "$FULL_PATH" << STUBEOF
---
title: ${topic}
type: stub
created: ${TODAY}
source: dreaming-rag-miss
status: todo
---

# ${topic}

> This document was automatically created because knowledge base searches
> for this topic returned no results. Please fill with content.

## Context
Created by Dreaming Run #${RUN_ID} on ${TODAY}.
STUBEOF
    VAULT_GAPS_FILLED=$((VAULT_GAPS_FILLED + 1))
    log "Vault stub created: $STUB_PATH"
  fi
done <<< "$TRIAGE_RESULT"

# =============================================================================
# PHASE 4: SKILL PROPOSALS
# =============================================================================

log "Phase 4: Checking skill proposals"

SKILL_PROPOSALS=0

FREQUENT_UNRESOLVED=$(autonomie_db "
  SELECT pattern_key, LEFT(description, 120), occurrence_count
  FROM error_patterns
  WHERE resolved = false AND occurrence_count >= 5
  ORDER BY occurrence_count DESC LIMIT 15;
" || echo "")

while IFS=$'\t' read -r pkey desc cnt; do
  [ -z "$pkey" ] && continue

  PKEY_ESC=$(echo "$pkey" | sed "s/'/''/g" | tr -cd 'a-zA-Z0-9_-' | head -c 60)
  DESC_ESC=$(echo "$desc" | sed "s/'/''/g" | tr -cd 'a-zA-Z0-9 _.,;:!?()-' | head -c 200)
  TARGET_SKILL="dreaming:${PKEY_ESC}"

  EXISTING=$(autonomie_db "
    SELECT status, recurrence_count FROM skill_proposals
    WHERE target_skill = '${TARGET_SKILL}' ORDER BY created_at DESC LIMIT 1;
  " || echo "")

  EXISTING_STATUS=$(echo "$EXISTING" | cut -f1)
  EXISTING_COUNT=$(echo "$EXISTING" | cut -f2)

  if [ "$EXISTING_STATUS" = "pending" ] || [ "$EXISTING_STATUS" = "auto_merged" ]; then
    continue
  fi

  if [ "$EXISTING_STATUS" = "rejected" ]; then
    if [ "${cnt:-0}" -le "$((${EXISTING_COUNT:-0} * 2))" ]; then
      continue
    fi
    log "Re-proposal: $pkey was rejected at ${EXISTING_COUNT}x, now ${cnt}x"
  fi

  autonomie_db_exec "
    INSERT INTO skill_proposals (proposal_type, target_skill, proposal_content, recurrence_count, confidence, status)
    VALUES (
      'NEW_RULE',
      '${TARGET_SKILL}',
      'Dreaming proposal: Pattern \"${PKEY_ESC}\" occurs ${cnt}x (previously: ${EXISTING_COUNT:-0}x). ${DESC_ESC}. Recommendation: Create guard or skill for prevention.',
      ${cnt:-1},
      LEAST(${cnt:-1}, 10),
      'pending'
    );
  " "$LOG" && SKILL_PROPOSALS=$((SKILL_PROPOSALS + 1))
  log "Skill proposal created: $pkey ($cnt occurrences)"
done <<< "$FREQUENT_UNRESOLVED"

# =============================================================================
# PHASE 5: DREAMING REPORT + AUDIT
# =============================================================================

DURATION=$(( $(date +%s) - START_TIME ))

log "Phase 5: Creating report"

REPORT_FILE="$DREAMING_DIR/${TODAY}.md"
cat > "$REPORT_FILE" << REPORTEOF
---
title: Dreaming Report ${TODAY}
type: dreaming-report
date: ${TODAY}
run_id: ${RUN_ID}
duration_seconds: ${DURATION}
---

# Dreaming Report - ${TODAY}

## Summary

| Metric | Value |
|--------|-------|
| Sessions analyzed | ${SESSION_COUNT} |
| Learnings applied | ${LEARNINGS_APPLIED} |
| Patterns updated | ${PATTERNS_UPDATED} |
| Playbooks created | ${PLAYBOOKS_CREATED} |
| Skill proposals | ${SKILL_PROPOSALS} |
| Vault gaps filled | ${VAULT_GAPS_FILLED} |
| Duration | ${DURATION}s |

## LLM Triage

\`\`\`
${TRIAGE_RESULT:-No triage performed}
\`\`\`

## Analyzed Sessions
$(for f in $SESSION_FILES; do echo "- $(basename "$f" 2>/dev/null)"; done)

## Git Activity
${GIT_SUMMARY:-No commits}
REPORTEOF

# Update audit trail
autonomie_db_exec "
  UPDATE dreaming_runs SET
    sessions_analyzed = $SESSION_COUNT,
    learnings_applied = $LEARNINGS_APPLIED,
    patterns_updated = $PATTERNS_UPDATED,
    playbooks_created = $PLAYBOOKS_CREATED,
    skill_proposals_created = $SKILL_PROPOSALS,
    rag_gaps_filled = $VAULT_GAPS_FILLED,
    vault_report_path = 'autonomie/dreaming/${TODAY}.md',
    duration_seconds = $DURATION,
    cost_usd = 0.00,
    status = 'completed'
  WHERE id = $RUN_ID;
" "$LOG"

# =============================================================================
# PHASE 6: NOTIFY + RAG REINDEX
# =============================================================================

TOTAL_ACTIONS=$((PLAYBOOKS_CREATED + LEARNINGS_APPLIED + PATTERNS_UPDATED + SKILL_PROPOSALS + VAULT_GAPS_FILLED))

if [ "$TOTAL_ACTIONS" -gt 0 ]; then
  autonomie_notify \
    "Dreaming ${TODAY}: ${TOTAL_ACTIONS} improvements" \
    "Dreaming found ${TOTAL_ACTIONS} improvements:
- ${PLAYBOOKS_CREATED} playbooks created
- ${LEARNINGS_APPLIED} learnings applied
- ${PATTERNS_UPDATED} error patterns updated
- ${SKILL_PROPOSALS} skill proposals
- ${VAULT_GAPS_FILLED} vault gaps filled

Report: autonomie/dreaming/${TODAY}.md" \
    "default"
else
  log "No improvements found"
fi

# RAG reindex if vault files were written
if [ "$PLAYBOOKS_CREATED" -gt 0 ] || [ "$VAULT_GAPS_FILLED" -gt 0 ]; then
  if [ -n "$RAG_INDEX_CMD" ]; then
    log "RAG reindex started"
    eval "$RAG_INDEX_CMD" >> "$LOG" 2>&1 || log "RAG reindex failed"
  fi
fi

log "====== Dreaming Run completed: ${TOTAL_ACTIONS} improvements in ${DURATION}s ======"
