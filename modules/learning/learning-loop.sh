#!/bin/bash
# =============================================================================
# LEARNING-LOOP - Analyzes RAG misses and error patterns
# Generates learning_items as improvement suggestions
#
# Cron: 0 5 * * * /path/to/autonomie-os/modules/learning/learning-loop.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOG="$LOG_DIR/learning-loop.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo "$TIMESTAMP: ====== Learning Loop Start ======" >> "$LOG"

# 1. Convert RAG misses to learning items (unprocessed misses, last 24h)
MISS_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM rag_misses WHERE resolved = false AND created_at > NOW() - INTERVAL '24 hours';
")

echo "$TIMESTAMP: RAG-Misses (24h): $MISS_COUNT" >> "$LOG"

if [ "${MISS_COUNT:-0}" -gt 0 ]; then
  autonomie_db_exec "
    INSERT INTO learning_items (source, lesson, applicable_to, occurrence_count)
    SELECT
      'rag_miss',
      'Knowledge base has no good coverage for: ' || substring(query, 1, 200),
      'vault',
      COUNT(*)
    FROM rag_misses
    WHERE resolved = false
      AND created_at > NOW() - INTERVAL '24 hours'
    GROUP BY substring(query, 1, 200)
    HAVING COUNT(*) >= 2
    ON CONFLICT DO NOTHING;

    UPDATE rag_misses SET resolved = true, resolved_by = 'learning-loop'
    WHERE resolved = false AND created_at > NOW() - INTERVAL '24 hours';
  " "$LOG"
fi

# 2. Convert high-occurrence error patterns to learning items
PATTERN_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM error_patterns
  WHERE resolved = false AND occurrence_count >= 5
  AND NOT EXISTS (
    SELECT 1 FROM learning_items
    WHERE lesson LIKE '%' || error_patterns.pattern_key || '%'
    AND source = 'error'
  );
")

echo "$TIMESTAMP: New Error Patterns (>=5x): $PATTERN_COUNT" >> "$LOG"

if [ "${PATTERN_COUNT:-0}" -gt 0 ]; then
  autonomie_db_exec "
    INSERT INTO learning_items (source, lesson, applicable_to, occurrence_count)
    SELECT
      'error',
      'Recurring problem: ' || pattern_key || ' - ' || COALESCE(description, ''),
      related_skill,
      occurrence_count
    FROM error_patterns
    WHERE resolved = false AND occurrence_count >= 5
    AND NOT EXISTS (
      SELECT 1 FROM learning_items
      WHERE lesson LIKE '%' || error_patterns.pattern_key || '%'
      AND source = 'error'
    )
    LIMIT 10;
  " "$LOG"
fi

# 3. Session learning (stage 2)
SESSION_LEARNER="$SCRIPT_DIR/session-learner.sh"
if [ -x "$SESSION_LEARNER" ]; then
  "$SESSION_LEARNER" 1 2>/dev/null || echo "$TIMESTAMP: Session learner failed" >> "$LOG"
fi

# 4. Learning consolidator (stage 3): cluster, deduplicate, report
CONSOLIDATOR="$SCRIPT_DIR/learning-consolidator.sh"
if [ -x "$CONSOLIDATOR" ]; then
  "$CONSOLIDATOR" 2>/dev/null || echo "$TIMESTAMP: Learning consolidator failed" >> "$LOG"
fi

# 5. Summary
TOTAL=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false;
")

echo "$TIMESTAMP: Open learning items total: $TOTAL" >> "$LOG"
echo "$TIMESTAMP: ====== Learning Loop Complete ======" >> "$LOG"
