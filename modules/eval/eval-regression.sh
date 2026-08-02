#!/bin/bash
# =============================================================================
# EVAL-REGRESSION - Detects regressions in bugfix tasks
#
# When a new bugfix targets the same repo+symptom as an older fix,
# the older task is marked as outcome=partial (likely regression).
#
# Cron: daily 04:00
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOOKBACK_DAYS=30

# This module requires a task management database (cockpit/tasks table)
if [ -z "$COCKPIT_DB" ]; then
  echo "COCKPIT_DB not configured. Skipping eval-regression."
  exit 0
fi

cockpit_db() {
  if [ -n "$DB_CONTAINER" ]; then
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$COCKPIT_DB" -t -A -c "$1" 2>/dev/null
  else
    PGPASSWORD="${DB_PASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$COCKPIT_DB" -t -A -c "$1" 2>/dev/null
  fi
}

log() {
  echo "[$(date -Iseconds)] eval-regression: $*"
}

# Find new bugfix tasks completed in the last 24h
new_bugfixes=$(cockpit_db "
  SELECT id, target_repo, LEFT(prompt, 200) AS prompt_preview
  FROM tasks
  WHERE category IN ('bug', 'ops', 'security')
    AND status = 'completed'
    AND completed_at > NOW() - INTERVAL '1 day'
    AND target_repo IS NOT NULL
  ORDER BY completed_at DESC
  LIMIT 20;
")

[ -z "$new_bugfixes" ] && { log "No new tasks (bug/ops/security)"; exit 0; }

while IFS='|' read -r new_task_id target_repo prompt_preview; do
  [ -z "$new_task_id" ] && continue

  # Extract keywords from prompt (first 5 significant words)
  keywords=$(echo "$prompt_preview" | tr '[:upper:]' '[:lower:]' | grep -oP '\b[a-z]{4,}\b' | sort -u | head -5 | tr '\n' '|' | sed 's/|$//')
  [ -z "$keywords" ] && continue

  # Search for older bugfix tasks in the same repo with similar keywords
  older_matches=$(cockpit_db "
    SELECT id FROM tasks
    WHERE category IN ('bug', 'ops', 'security')
      AND status = 'completed'
      AND target_repo = '${target_repo}'
      AND id != '${new_task_id}'
      AND completed_at > NOW() - INTERVAL '${LOOKBACK_DAYS} days'
      AND completed_at < (SELECT completed_at FROM tasks WHERE id = '${new_task_id}')
      AND outcome IS NULL
      AND prompt ~* '(${keywords})'
    ORDER BY completed_at DESC
    LIMIT 3;
  ")

  [ -z "$older_matches" ] && continue

  while read -r older_task_id; do
    [ -z "$older_task_id" ] && continue
    cockpit_db "
      UPDATE tasks
      SET outcome = 'partial',
          outcome_reason = 'Possible regression: new bugfix ${new_task_id} for same repo/symptom',
          outcome_evaluated_at = NOW()
      WHERE id = '${older_task_id}' AND outcome IS NULL;
    "
    log "Task $older_task_id -> outcome=partial (regression by $new_task_id in $target_repo)"
  done <<< "$older_matches"
done <<< "$new_bugfixes"

log "Done"
