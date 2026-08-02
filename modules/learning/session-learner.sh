#!/bin/bash
# =============================================================================
# SESSION LEARNER: Extracts lessons learned from session logs
# =============================================================================
# Analyzes new/modified session logs and creates learning_items in the DB.
#
# Called by learning-loop.sh (daily)
# Can also be run manually: ./session-learner.sh [days]
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOG="$LOG_DIR/learning-loop.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
DAYS="${1:-1}"

echo "$TIMESTAMP: --- Session Learner Start (${DAYS}d) ---" >> "$LOG"

# Find sessions modified in the last N days
RECENT_SESSIONS=$(find "$SESSIONS_DIR" -name "*.md" -mtime "-${DAYS}" -type f 2>/dev/null)
COUNT=$(echo "$RECENT_SESSIONS" | grep -c ".md" 2>/dev/null || echo "0")

echo "$TIMESTAMP: New/modified sessions: $COUNT" >> "$LOG"

if [ "$COUNT" -eq 0 ]; then
  echo "$TIMESTAMP: No new sessions, skipping" >> "$LOG"
  exit 0
fi

for SESSION in $RECENT_SESSIONS; do
  FILENAME=$(basename "$SESSION")

  # Check if already processed
  EXISTS=$(autonomie_db "
    SELECT COUNT(*) FROM learning_items WHERE lesson LIKE '%${FILENAME}%' AND source = 'session';
  ")

  if [ "${EXISTS:-0}" -gt 0 ]; then
    continue
  fi

  # Extract key findings from the session
  LESSONS=$(grep -iE "^\s*[-*]\s.*(open|lesson|insight|decision|fix|workaround|problem|solution|cause|error|change|recommendation|important|critical)" "$SESSION" 2>/dev/null | head -5)
  # Fallback: look for section headers with actual content below them
  if [ -z "$LESSONS" ]; then
    LESSONS=$(awk '
      /^##.*(result|insight|conclusion|summary|change|completed)/i {
        header=$0; next
      }
      header && /^##/ { header=""; next }
      header && /^>/ { next }
      header && /^[[:space:]]*$/ { next }
      header && /[[:alpha:]]/ { print header; header="" }
    ' "$SESSION" 2>/dev/null | head -3)
  fi

  if [ -n "$LESSONS" ]; then
    FIRST_LESSON=$(echo "$LESSONS" | head -1 | sed "s/^[[:space:]]*[-*][[:space:]]*//" | sed "s/'/''/g" | cut -c1-500)

    autonomie_db_exec "
      INSERT INTO learning_items (source, lesson, applicable_to, occurrence_count)
      VALUES ('session', 'Session ${FILENAME}: ${FIRST_LESSON}', NULL, 1)
      ON CONFLICT DO NOTHING;
    " "$LOG"

    echo "$TIMESTAMP: Extracted from $FILENAME" >> "$LOG"
  fi
done

echo "$TIMESTAMP: --- Session Learner Complete ---" >> "$LOG"
