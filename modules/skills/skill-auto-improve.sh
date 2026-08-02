#!/bin/bash
# =============================================================================
# SKILL-AUTO-IMPROVE - Automated skill optimization pipeline
#
# Phase 1 (Cron, morning): SQL pattern collection + LLM pre-assessment -> staging
# Phase 2 (Interactive session): Agent executes the actual improvements
#
# Cron: 0 7 * * * /path/to/autonomie-os/modules/skills/skill-auto-improve.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOGFILE="$LOG_DIR/skill-auto-improve-$(date +%Y-%m-%d).log"
MAX_AUTO_PER_DAY=${MAX_AUTO_FIXES_PER_DAY:-3}

mkdir -p "$(dirname "$LOGFILE")" "$STAGING_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "=== Skill Auto-Improve Phase 1: Data Collection ==="

# =============================================================================
# PHASE 1: Collect data from autonomie DB
# =============================================================================

# Daily limit check
AUTO_TODAY=$(autonomie_db "
  SELECT COUNT(*) FROM skill_decisions
  WHERE decision_type = 'autonomous' AND was_applied = true
  AND created_at::date = CURRENT_DATE;
" || echo "0")

if [ "${AUTO_TODAY:-0}" -ge "$MAX_AUTO_PER_DAY" ]; then
  log "Daily limit reached ($AUTO_TODAY/$MAX_AUTO_PER_DAY). Skipping."
  autonomie_notify "Skill Auto-Improve - Daily limit" "Daily limit reached ($AUTO_TODAY/$MAX_AUTO_PER_DAY). No action needed." "low"
  exit 0
fi

# Load actionable error patterns
PATTERN_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM error_patterns
  WHERE resolved = false
    AND (addressed = false OR addressed IS NULL)
    AND occurrence_count >= 2;
" || echo "0")

log "Actionable patterns: $PATTERN_COUNT"

if [ "${PATTERN_COUNT:-0}" -eq 0 ]; then
  log "No actionable patterns. Done."
  exit 0
fi

# Fetch pattern details
PATTERNS=$(autonomie_db "
  SELECT json_agg(row)
  FROM (
    SELECT json_build_object(
      'id', id,
      'pattern_name', pattern_key,
      'skill_name', COALESCE(related_skill, 'unknown'),
      'occurrence_count', occurrence_count,
      'last_seen', last_seen::text,
      'description', substring(description, 1, 200),
      'category', category
    ) AS row
    FROM error_patterns
    WHERE resolved = false
      AND (addressed = false OR addressed IS NULL)
      AND occurrence_count >= 3
    ORDER BY occurrence_count DESC
    LIMIT 10
  ) sub;
" || echo "[]")

# Recent skill decisions (context)
RECENT_DECISIONS=$(autonomie_db "
  SELECT json_agg(row)
  FROM (
    SELECT json_build_object(
      'skill_name', skill_name,
      'decision_type', decision_type,
      'judge_decision', judge_decision,
      'was_applied', was_applied,
      'created_at', created_at::text
    ) AS row
    FROM skill_decisions
    WHERE created_at > NOW() - INTERVAL '7 days'
    ORDER BY created_at DESC
    LIMIT 10
  ) sub;
" || echo "[]")

# Skill metrics
SKILL_METRICS=$(autonomie_db "
  SELECT json_agg(json_build_object(
    'skill_name', skill_name,
    'total_uses', total_uses,
    'success_rate', success_rate,
    'avg_duration_ms', avg_duration_ms,
    'last_used', last_used
  ))
  FROM (
    SELECT
      skill_name,
      COUNT(*) AS total_uses,
      ROUND(AVG(CASE WHEN success THEN 100 ELSE 0 END)::numeric, 2) AS success_rate,
      ROUND(AVG(duration_minutes * 60000)::numeric, 0) AS avg_duration_ms,
      MAX(created_at)::text AS last_used
    FROM skill_metrics
    WHERE invoked = true
    GROUP BY skill_name
    ORDER BY COUNT(*) DESC
    LIMIT 15
  ) sub;
" || echo "[]")

# RAG misses
RAG_MISSES=$(autonomie_db "
  SELECT json_agg(json_build_object(
    'query', query,
    'miss_count', cnt,
    'last_miss', last_miss
  ))
  FROM (
    SELECT query, COUNT(*) AS cnt, MAX(created_at)::text AS last_miss
    FROM rag_misses
    WHERE resolved = false
    GROUP BY query
    HAVING COUNT(*) >= 3
    ORDER BY COUNT(*) DESC
    LIMIT 10
  ) sub;
" || echo "[]")

log "Data collected: $PATTERN_COUNT patterns, decisions, metrics, RAG misses"

# =============================================================================
# PHASE 2: LLM Pre-Assessment
# =============================================================================

log "Phase 2: LLM triage"

TRIAGE_INPUT="You are a skill optimization analyst. Analyze these error patterns from an AI agent system and assess: (1) Which patterns are most critical? (2) Which could be automatically fixed (e.g. timeout increase, fallback logic)? (3) Which need human decision? Answer in max 200 words, structured by priority. No markdown.

ERROR PATTERNS:
$(echo "$PATTERNS" | jq -r '.[] | "- \(.pattern_name) (\(.skill_name)): \(.occurrence_count)x, last seen \(.last_seen) - \(.description)"' 2>/dev/null || echo "$PATTERNS")

RAG MISSES (frequent failed searches):
$(echo "$RAG_MISSES" | jq -r '.[] | "- \(.query): \(.miss_count)x"' 2>/dev/null || echo "none")

SKILL PERFORMANCE:
$(echo "$SKILL_METRICS" | jq -r '.[] | "- \(.skill_name): \(.total_uses) uses, \(.success_rate)% success"' 2>/dev/null || echo "no data")"

TRIAGE_TEXT=$(autonomie_llm "$TRIAGE_INPUT" 250 0.3) || TRIAGE_TEXT="LLM triage failed"
log "LLM triage: $(echo "$TRIAGE_TEXT" | head -3)"

# =============================================================================
# PHASE 3: Staging File
# =============================================================================

STAGING_FILE="$STAGING_DIR/skill-improve-$(date +%Y-%m-%d).json"

cat > "$STAGING_FILE" << STAGING_EOF
{
  "date": "$(date '+%Y-%m-%d')",
  "collected_at": "$(date '+%Y-%m-%d %H:%M:%S')",
  "pattern_count": ${PATTERN_COUNT:-0},
  "auto_today": ${AUTO_TODAY:-0},
  "max_auto_per_day": $MAX_AUTO_PER_DAY,
  "patterns": ${PATTERNS:-"[]"},
  "recent_decisions": ${RECENT_DECISIONS:-"[]"},
  "skill_metrics": ${SKILL_METRICS:-"[]"},
  "rag_misses": ${RAG_MISSES:-"[]"},
  "llm_triage": $(echo "$TRIAGE_TEXT" | jq -Rs .)
}
STAGING_EOF

log "Staging file: $STAGING_FILE"

# =============================================================================
# PHASE 4: Notify + Summary
# =============================================================================

if echo "$TRIAGE_TEXT" | grep -qi "critical\|security\|immediate"; then
  ICON="WARNING"
  PRIO="high"
elif [ "${PATTERN_COUNT:-0}" -gt 5 ]; then
  ICON="REVIEW"
  PRIO="default"
else
  ICON="INFO"
  PRIO="low"
fi

autonomie_notify \
  "[$ICON] Skill-Improve: ${PATTERN_COUNT} patterns" \
  "${PATTERN_COUNT} actionable patterns found.

LLM Triage:
$(echo "$TRIAGE_TEXT" | head -6)

Staging file: $STAGING_FILE
Next step: Review and apply improvements." \
  "$PRIO"

log "=== Skill Auto-Improve Phase 1 completed ==="

# Clean up old staging files
find "$STAGING_DIR" -name "skill-improve-*.json" -mtime +14 -delete 2>/dev/null || true
