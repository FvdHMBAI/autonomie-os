#!/bin/bash
# =============================================================================
# NIGHTLY BRAIN SESSION - The vault THINKS, not just collects
#
# Unlike dreaming.sh (analyzes sessions, writes reports passively),
# the brain analyzes EVERYTHING and generates ACTIONS actively.
#
# What it does:
# 1. Prioritize learning items -> top 5 actionable tasks
# 2. Analyze RAG misses -> identify vault gaps
# 3. Detect cross-domain patterns -> suggest connections
# 4. Generate ideas -> brain memo
# 5. Check vault drift -> identify missing documentation
#
# Cron: 0 4 * * * /path/to/autonomie-os/modules/brain/nightly-brain.sh
# Safeguards:
# - Writes ONLY to vault + logs, no code changes
# - No PII (sessions are anonymized)
# - Max 5 minutes LLM timeout per analysis
# - Bypass: touch /tmp/autonomie/brain-skip
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOG="$LOG_DIR/nightly-brain.log"
TODAY=$(date +%Y-%m-%d)
BRAIN_DIR="$VAULT_DIR/autonomie/brain-memos"
MEMO_FILE="$BRAIN_DIR/BRAIN_MEMO_$TODAY.md"

mkdir -p "$BRAIN_DIR" "$(dirname "$LOG")" 2>/dev/null

log() { echo "$(date -Iseconds) $1" >> "$LOG"; }

# Guards
SKIP_FILE="$LOCKFILE_DIR/brain-skip"
if [ -f "$SKIP_FILE" ]; then
  rm -f "$SKIP_FILE"
  log "bypass"
  exit 0
fi

log "====== Nightly Brain Session Start ======"

if [ -n "$ANTHROPIC_API_KEY" ]; then
  log "LLM: Anthropic ($ANTHROPIC_MODEL) primary, Ollama ($OLLAMA_MODEL) fallback"
elif curl -s --max-time 5 "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
  log "LLM: Ollama only ($OLLAMA_MODEL), no API key"
else
  log "ERROR: Neither Anthropic API key nor Ollama available"
  exit 1
fi

# =============================================================================
# PHASE 1: Learning Items -> Prioritize top 5
# =============================================================================
log "Phase 1: Analyzing learning items"

TOP_ITEMS=$(autonomie_db "
  SELECT source || ': ' || LEFT(lesson, 150) || ' (x' || occurrence_count || ')'
  FROM learning_items
  WHERE applied = false
  ORDER BY occurrence_count DESC, created_at DESC
  LIMIT 15;
" | head -15)

ITEM_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false;
")

log "Phase 1: $ITEM_COUNT open items, top 15 fetched"

if [ -n "$TOP_ITEMS" ]; then
  PRIO_PROMPT="You are an AI product manager. Here are open improvement suggestions for a software system.
Choose the 5 MOST IMPORTANT ones and formulate them as concrete, actionable tasks.

Format per task:
- PRIORITY: [high/medium]
- TASK: [What exactly to do]
- REASONING: [Why this one]
- AREA: [Which app/skill]

Open items:
$TOP_ITEMS

Answer ONLY with the 5 tasks, no intro/outro. Max 30 lines."

  PRIO_RESULT=$(autonomie_llm "$PRIO_PROMPT" 1024 0.4) || PRIO_RESULT=""
  log "Phase 1: Prioritization completed"
else
  PRIO_RESULT="No open learning items."
fi

# =============================================================================
# PHASE 2: RAG Misses -> Identify vault gaps
# =============================================================================
log "Phase 2: Analyzing RAG misses"

RAG_MISSES=$(autonomie_db "
  SELECT LEFT(query, 120) || ' (x' || COUNT(*) || ')'
  FROM rag_misses
  WHERE resolved = false
  GROUP BY LEFT(query, 120)
  HAVING COUNT(*) >= 2
  ORDER BY COUNT(*) DESC
  LIMIT 10;
")

MISS_TOTAL=$(autonomie_db "
  SELECT COUNT(*) FROM rag_misses WHERE resolved = false;
")

log "Phase 2: $MISS_TOTAL unresolved RAG misses"

if [ -n "$RAG_MISSES" ]; then
  GAP_PROMPT="You are analyzing search queries that returned NO results in a knowledge vault.
For each query: What vault document SHOULD exist or be supplemented?

Format:
- GAP: [What is missing]
- SUGGESTION: [Which file to create/supplement, path suggestion]
- URGENCY: [high if core knowledge, low if edge topic]

Misses (most frequent first):
$RAG_MISSES

Max 20 lines. Only the top 5 gaps."

  GAP_RESULT=$(autonomie_llm "$GAP_PROMPT" 1024 0.3) || GAP_RESULT=""
  log "Phase 2: Gap analysis completed"
else
  GAP_RESULT="No frequent RAG misses."
fi

# =============================================================================
# PHASE 3: Cross-Domain Patterns (last 7 sessions)
# =============================================================================
log "Phase 3: Cross-domain patterns"

CURRENT_MONTH=$(date +%Y-%m)
WEEK_AGO=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)

SESSION_SUMMARIES=""
COUNT=0
for month_dir in "$SESSIONS_DIR/$CURRENT_MONTH" "$SESSIONS_DIR/$(date -d '7 days ago' +%Y-%m 2>/dev/null || echo "$CURRENT_MONTH")"; do
  [ -d "$month_dir" ] || continue
  while IFS= read -r f; do
    [ $COUNT -ge 10 ] && break
    fname=$(basename "$f")
    fdate="${fname:0:10}"
    if [[ "$fdate" > "$WEEK_AGO" || "$fdate" == "$WEEK_AGO" ]]; then
      SUMMARY=$(grep -E "^#|Root Cause|Result|Fix:|Commit:" "$f" 2>/dev/null | head -8)
      if [ -n "$SUMMARY" ]; then
        SESSION_SUMMARIES="$SESSION_SUMMARIES
--- $fname ---
$SUMMARY"
        COUNT=$((COUNT + 1))
      fi
    fi
  done < <(find "$month_dir" -name "*.md" -type f 2>/dev/null | sort -r)
done

if [ -n "$SESSION_SUMMARIES" ] && [ $COUNT -ge 3 ]; then
  CROSS_PROMPT="You are analyzing session logs from different apps in a software system.
Find CROSS-CONNECTIONS: Same problems in different apps, repeating patterns,
solutions from app A that would also help in app B.

Also find CREATIVE IDEAS: What NEW things could be combined from existing features?

Format:
## Cross-Connections
- [Pattern]: [Where it occurs] -> [What follows]

## Creative Ideas
- [Idea]: [Why it could work] (Effort: [low/medium/high])

Sessions:
$SESSION_SUMMARIES

Max 25 lines. Only real insights, no filler."

  CROSS_RESULT=$(autonomie_llm "$CROSS_PROMPT" 1024 0.6) || CROSS_RESULT=""
  log "Phase 3: Cross-domain completed ($COUNT sessions)"
else
  CROSS_RESULT="Too few sessions this week for cross-domain analysis."
fi

# =============================================================================
# PHASE 4: Vault Drift (missing documentation)
# =============================================================================
log "Phase 4: Vault drift check"

DRIFT_RESULT=""
DRIFT_CHECK="$SCRIPT_DIR/../eval/drift-check.py"
if [ -x "$DRIFT_CHECK" ]; then
  DRIFT_RESULT=$(timeout 300 python3 "$DRIFT_CHECK" --json 2>/dev/null | head -30) || true
  log "Phase 4: Drift check completed"
else
  DRIFT_RESULT="drift-check.py not found."
fi

# =============================================================================
# PHASE 5: Write Brain Memo
# =============================================================================
log "Phase 5: Generating brain memo"

cat > "$MEMO_FILE" << MEMO
---
title: Brain Memo $TODAY
type: brain-memo
date: $TODAY
learning_items_open: ${ITEM_COUNT:-0}
rag_misses_open: ${MISS_TOTAL:-0}
sessions_analyzed: $COUNT
---

# Brain Memo - $TODAY

> Automatically generated by nightly-brain.sh
> The vault has been thinking. Here are the results.

## 1. Top 5 Priorities (from ${ITEM_COUNT:-0} open learning items)

$PRIO_RESULT

## 2. Knowledge Gaps (from ${MISS_TOTAL:-0} RAG misses)

$GAP_RESULT

## 3. Cross-Domain Patterns and Ideas

$CROSS_RESULT

## 4. Vault Drift (missing documentation)

\`\`\`
$DRIFT_RESULT
\`\`\`

## Metrics

| Metric | Value |
|--------|-------|
| Learning items open | ${ITEM_COUNT:-0} |
| RAG misses unresolved | ${MISS_TOTAL:-0} |
| Sessions analyzed | $COUNT |
| Date | $TODAY |

---
*Generated: $(date -Iseconds) by nightly-brain.sh*
MEMO

log "Phase 5: Memo written -> $MEMO_FILE"

# =============================================================================
# PHASE 6: Notification
# =============================================================================
log "Phase 6: Notification"

autonomie_notify \
  "Brain Memo $TODAY" \
  "Brain Memo $TODAY: ${ITEM_COUNT:-0} open learnings, ${MISS_TOTAL:-0} RAG gaps, $COUNT sessions analyzed." \
  "low"

log "====== Nightly Brain Session Complete ======"

# =============================================================================
# CONSOLIDATED: Run sub-modules
# =============================================================================

LEARNING_DIR="$SCRIPT_DIR/../learning"

# brain-rag-filler
log "--- Starting consolidated: brain-rag-filler ---"
"$SCRIPT_DIR/brain-rag-filler.sh" >> "$LOG" 2>&1 || log "WARNING: brain-rag-filler failed"

# learning-loop
log "--- Starting consolidated: learning-loop ---"
"$LEARNING_DIR/learning-loop.sh" >> "$LOG" 2>&1 || log "WARNING: learning-loop failed"

# dreaming-local (only on Sundays)
if [ "$(date +%u)" = "7" ]; then
  log "--- Starting consolidated: dreaming-local (Sunday) ---"
  "$SCRIPT_DIR/../dreaming/dreaming-local.sh" >> "$LOG" 2>&1 || log "WARNING: dreaming-local failed"
fi

# learning-apply
log "--- Starting consolidated: learning-apply ---"
"$LEARNING_DIR/learning-apply.sh" 2>&1 | tail -5 >> "$LOG" || log "WARNING: learning-apply failed"

log "====== Nightly Brain + Consolidated Jobs Complete ======"
