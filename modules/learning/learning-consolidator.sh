#!/bin/bash
# =============================================================================
# LEARNING CONSOLIDATOR (Stage 3): Learning Items -> Actionable Improvements
# =============================================================================
# Analyzes open learning_items, clusters by topic, consolidates duplicates,
# and generates prioritized improvement suggestions.
#
# Runs as part of the Learning Loop (after session-learner.sh)
# Can also be run manually: ./learning-consolidator.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOG="$LOG_DIR/learning-loop.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
REPORT_DIR="$VAULT_DIR/autonomie/skill-evolution"
REPORT="$REPORT_DIR/learning-report-$(date +%Y-%m-%d).md"

log() { echo "$TIMESTAMP: $*" >> "$LOG"; }

log "--- Learning Consolidator Start ---"

mkdir -p "$REPORT_DIR"

# 1. Count open items
OPEN_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false;
" || echo "0")

log "Open learning items: $OPEN_COUNT"

if [ "${OPEN_COUNT:-0}" -eq 0 ]; then
  log "No open items, skipping"
  exit 0
fi

# 2. Cluster analysis: group by keywords
CLUSTERS=$(autonomie_db "
  WITH words AS (
    SELECT unnest(string_to_array(
      regexp_replace(lower(lesson), '[^a-z0-9 ]', ' ', 'g'),
      ' '
    )) AS word
    FROM learning_items
    WHERE applied = false
  )
  SELECT word || ':' || COUNT(*)
  FROM words
  WHERE length(word) > 5
    AND word NOT IN ('session', 'recurring', 'problem', 'completed', 'status',
                     'changes', 'created', 'updated', 'version', 'added')
  GROUP BY word
  HAVING COUNT(*) >= 5
  ORDER BY COUNT(*) DESC
  LIMIT 20;
")

log "Top clusters: $(echo "$CLUSTERS" | tr '\n' ', ')"

# 3. Duplicate detection: mark items with very similar lessons
DUPES_MARKED=$(autonomie_db "
  WITH dupes AS (
    SELECT l1.id
    FROM learning_items l1
    JOIN learning_items l2 ON l1.id > l2.id
      AND l1.source = l2.source
      AND left(l1.lesson, 80) = left(l2.lesson, 80)
    WHERE l1.applied = false AND l2.applied = false
  )
  UPDATE learning_items SET applied = true, applied_at = NOW()
  WHERE id IN (SELECT id FROM dupes)
  RETURNING id;
" | wc -l | tr -d ' ')

log "Duplicates marked: $DUPES_MARKED"

# 4. Categorize remaining items by topic
DEPLOYMENT_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false
  AND lesson ~* '(deploy|container|docker|traefik|502|restart)';
" || echo "0")

AUTH_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false
  AND lesson ~* '(auth|login|rls|password|token|session|jwt)';
" || echo "0")

DB_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false
  AND lesson ~* '(postgres|supabase|migration|schema|query|index|sql)';
" || echo "0")

TESTING_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false
  AND lesson ~* '(test|e2e|playwright|nightly|cypress|jest)';
" || echo "0")

RAG_COUNT=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false
  AND lesson ~* '(rag|vault|embedding|ollama|chunk|semantic|search)';
" || echo "0")

REMAINING=$(autonomie_db "
  SELECT COUNT(*) FROM learning_items WHERE applied = false;
" || echo "0")

# 5. Extract top 5 high-priority lessons (by frequency)
TOP_LESSONS=$(autonomie_db "
  SELECT '- ' || substring(lesson, 1, 200)
  FROM learning_items
  WHERE applied = false AND source = 'error'
  ORDER BY occurrence_count DESC
  LIMIT 5;
")

TOP_SESSION_LESSONS=$(autonomie_db "
  SELECT '- ' || substring(lesson, 1, 200)
  FROM learning_items
  WHERE applied = false AND source = 'session'
  ORDER BY created_at DESC
  LIMIT 10;
")

# 6. Generate report
cat > "$REPORT" << REPORTEOF
---
title: Learning Consolidator Report
type: autonomie-report
date: $(date +%Y-%m-%d)
---

# Learning Consolidator Report $(date +%Y-%m-%d)

## Summary

| Metric | Value |
|--------|-------|
| Open items (before cleanup) | $OPEN_COUNT |
| Duplicates removed | $DUPES_MARKED |
| Remaining items | $REMAINING |

## Topic Clusters

| Category | Item Count | Skill Area |
|----------|-----------|------------|
| Deployment/Infra | $DEPLOYMENT_COUNT | infrastructure, deployment |
| Auth/Security | $AUTH_COUNT | security, debugging |
| Database | $DB_COUNT | debugging, infrastructure |
| Testing | $TESTING_COUNT | quality-gate |
| RAG/Vault | $RAG_COUNT | knowledge-update |

## Top Error Patterns (highest priority)

$TOP_LESSONS

## Recent Session Insights

$TOP_SESSION_LESSONS

## Word Clusters (>= 5 occurrences)

\`\`\`
$(echo "$CLUSTERS" | head -15)
\`\`\`

## Recommended Actions

1. **Fix high-occurrence error patterns first**
2. **Incorporate session insights into skills** (new rules, gotchas, workarounds)
3. **Further consolidate duplicate learning items**
4. **Close RAG miss gaps** (document topics with poor coverage)

REPORTEOF

log "Report written: $REPORT"

# 7. Archive old processed items (older than 30 days)
ARCHIVED=$(autonomie_db "
  DELETE FROM learning_items
  WHERE applied = true
    AND applied_at < NOW() - INTERVAL '30 days'
  RETURNING id;
" | grep -c "^" || echo "0")

log "Archived (>30d): $ARCHIVED"
log "--- Learning Consolidator Complete ---"
