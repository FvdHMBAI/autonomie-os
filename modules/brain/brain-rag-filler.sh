#!/bin/bash
# =============================================================================
# BRAIN RAG-FILLER - Actively fills knowledge gaps in the vault
#
# Analyzes RAG misses (search queries with no results), identifies which
# vault document is missing or incomplete, and creates stubs.
#
# Cron: Runs as part of nightly-brain.sh
# Safeguards:
# - Creates ONLY stubs with TODO markers, no finished documents
# - Max 5 stubs per run (to avoid flooding)
# - No PII
# - Bypass: touch /tmp/autonomie/rag-filler-skip
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOG="$LOG_DIR/brain-rag-filler.log"
TODAY=$(date +%Y-%m-%d)
MAX_STUBS=${MAX_STUBS_PER_RUN:-5}
CREATED=0

mkdir -p "$(dirname "$LOG")" 2>/dev/null
log() { echo "$(date -Iseconds) $1" >> "$LOG"; }

# Guards
SKIP_FILE="$LOCKFILE_DIR/rag-filler-skip"
[ -f "$SKIP_FILE" ] && { rm -f "$SKIP_FILE"; log "bypass"; exit 0; }

HAS_LLM=false
if [ -n "$ANTHROPIC_API_KEY" ]; then
  HAS_LLM=true
elif curl -s --max-time 5 "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
  HAS_LLM=true
fi
if [ "$HAS_LLM" = "false" ]; then
  log "ERROR: Neither Anthropic API key nor Ollama available"
  exit 1
fi

log "====== RAG-Filler Start ======"

# Fetch most frequent unresolved RAG misses (grouped, min 2x)
MISSES=$(autonomie_db "
  SELECT LEFT(query, 200)
  FROM rag_misses
  WHERE resolved = false
  GROUP BY LEFT(query, 200)
  HAVING COUNT(*) >= 2
  ORDER BY COUNT(*) DESC
  LIMIT $MAX_STUBS;
")

if [ -z "$MISSES" ]; then
  log "No frequent RAG misses. Done."
  exit 0
fi

MISS_COUNT=$(echo "$MISSES" | wc -l)
log "$MISS_COUNT frequent RAG miss clusters found"

while IFS= read -r miss; do
  [ -z "$miss" ] && continue
  [ $CREATED -ge $MAX_STUBS ] && break

  # Check if a matching file now exists (may have been created after the miss)
  if [ -n "$RAG_SEARCH_CMD" ]; then
    SEARCH_RESULT=$(eval "$RAG_SEARCH_CMD" "$miss" 1 2>/dev/null | head -2) || true
    if [ -n "$SEARCH_RESULT" ] && echo "$SEARCH_RESULT" | grep -qv "None"; then
      SCORE=$(echo "$SEARCH_RESULT" | grep -oP '\[[\d.]+\]' 2>/dev/null | head -1 | tr -d '[]') || true
      if [ -n "$SCORE" ] && (( $(echo "$SCORE > 0.6" | bc -l 2>/dev/null || echo 0) )); then
        log "Miss '$miss' now has a hit (score $SCORE), skipping"
        autonomie_db_exec \
          "UPDATE rag_misses SET resolved = true, resolved_by = 'rag-filler-found' WHERE query LIKE '$(echo "$miss" | sed "s/'/''/g")%' AND resolved = false;" \
          "$LOG"
        continue
      fi
    fi
  fi

  # Ask LLM: what should be documented?
  PROMPT="A search query in a knowledge vault returned no results:
\"$miss\"

The vault has this folder structure:
architecture/    (ADRs, API docs, domain models)
features/        (Feature documentation per app)
known-issues/    (Known problems and workarounds)
playbooks/       (Operational playbooks)

Task:
1. In which folder should the answer to this query live?
2. What should the file be named? (UPPERCASE, underscores, .md)
3. What sections should the file have?
4. What is the likely content? (bullet points, 5-10 lines)

Answer ONLY with:
FOLDER: <folder>
FILE: <filename.md>
SECTIONS: <comma-separated>
CONTENT: <bullet points>

No explanation, no intro."

  RESPONSE=$(autonomie_llm "$PROMPT" 512 0.3) || RESPONSE=""

  if [ -z "$RESPONSE" ]; then
    log "LLM failed for: $miss"
    continue
  fi

  FOLDER=$(echo "$RESPONSE" | grep -oP 'FOLDER:\s*\K.*' | head -1 | xargs)
  FILE=$(echo "$RESPONSE" | grep -oP 'FILE:\s*\K.*' | head -1 | xargs)
  CONTENT=$(echo "$RESPONSE" | sed -n '/CONTENT:/,$ p' | tail -n +1)

  if [ -z "$FOLDER" ] || [ -z "$FILE" ]; then
    log "Could not parse folder/file for: $miss"
    continue
  fi

  FULL_PATH="$VAULT_DIR/$FOLDER/$FILE"
  if [ -f "$FULL_PATH" ]; then
    log "File already exists: $FULL_PATH, skipping"
    continue
  fi

  mkdir -p "$VAULT_DIR/$FOLDER" 2>/dev/null

  cat > "$FULL_PATH" << STUB
---
title: $(echo "$FILE" | sed 's/\.md$//' | tr '_' ' ')
date: $TODAY
status: stub
created_by: brain-rag-filler
trigger_query: "$miss"
---

# $(echo "$FILE" | sed 's/\.md$//' | tr '_' ' ')

> **STUB** - Automatically created because the search query "$miss" returned no results.
> Please fill with actual content.

$CONTENT

---
*Created: $(date -Iseconds) by brain-rag-filler.sh*
*Trigger: RAG miss "$miss"*
STUB

  CREATED=$((CREATED + 1))
  log "Stub created: $FULL_PATH"

  autonomie_db_exec \
    "UPDATE rag_misses SET resolved = true, resolved_by = 'rag-filler-stub' WHERE query LIKE '$(echo "$miss" | sed "s/'/''/g")%' AND resolved = false;" \
    "$LOG"

done <<< "$MISSES"

# RAG reindex if stubs were created
if [ $CREATED -gt 0 ] && [ -n "$RAG_INDEX_CMD" ]; then
  log "RAG reindex ($CREATED stubs created)"
  eval "$RAG_INDEX_CMD" >> "$LOG" 2>&1 &
fi

log "====== RAG-Filler Complete: $CREATED stubs created ======"
