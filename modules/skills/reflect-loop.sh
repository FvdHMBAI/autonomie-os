#!/bin/bash
# =============================================================================
# REFLECT-LOOP - Weekly learning scan, suggests crystallization
#
# Scans all learnings.md files for entries with Score >= 4 AND Runs >= 3
# that are NOT yet crystallized. Reports candidates via notification.
#
# Cron: 0 8 * * 0 (Sundays 08:00)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

CANDIDATES=""
TOTAL=0

for learnings in "$SKILLS_DIR"/*/learnings.md; do
  [ -f "$learnings" ] || continue
  skill=$(basename "$(dirname "$learnings")")

  while IFS= read -r line; do
    block_start=$(grep -n "^## " "$learnings" | grep -B1 "$line" 2>/dev/null | head -1 | cut -d: -f1)
    [ -z "$block_start" ] && continue

    # Skip if already crystallized
    if sed -n "${block_start},/^## /p" "$learnings" | grep -qi "CRYSTALLIZED"; then
      continue
    fi

    score=$(sed -n "${block_start},/^## /p" "$learnings" 2>/dev/null | grep -oP 'Score:\s*\K[0-9]+' | head -1)
    runs=$(sed -n "${block_start},/^## /p" "$learnings" 2>/dev/null | grep -oP 'Runs:\s*\K[0-9]+' | head -1)

    if [ -n "$score" ] && [ -n "$runs" ] && [ "$score" -ge 4 ] && [ "$runs" -ge 3 ]; then
      title=$(echo "$line" | sed 's/^## [0-9-]*: //')
      CANDIDATES="${CANDIDATES}
- ${skill}: ${title} (Score ${score}, Runs ${runs})"
      TOTAL=$((TOTAL + 1))
    fi
  done < <(grep "^## [0-9]" "$learnings" 2>/dev/null)
done

if [ "$TOTAL" -gt 0 ]; then
  autonomie_notify \
    "Reflect-Loop: ${TOTAL} crystallization candidates" \
    "Learnings ready for crystallization (Score>=4, Runs>=3):
${CANDIDATES}

Action: Promote proven patterns into skill definitions." \
    "default"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S'): Reflect-Loop: ${TOTAL} candidates found" >> "$LOG_DIR/reflect-loop.log"
