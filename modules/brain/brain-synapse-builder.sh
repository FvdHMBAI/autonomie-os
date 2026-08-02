#!/bin/bash
# =============================================================================
# BRAIN SYNAPSE BUILDER - Finds and creates cross-links in the vault
#
# Uses RAG similarity search to find documents that are thematically related
# but have no [[links]] to each other. Suggests connections and adds
# "See also" sections.
#
# Cron: 0 5 * * 0 (Sunday 05:00, after Dreaming)
# Safeguards:
# - ONLY adds "See also" sections, does not modify existing content
# - Max 10 links per run
# - No PII
# - Bypass: touch /tmp/autonomie/synapse-skip
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../config.sh
source "$SCRIPT_DIR/../../config.sh"

LOG="$LOG_DIR/brain-synapse.log"
TODAY=$(date +%Y-%m-%d)
MAX_LINKS=${MAX_SYNAPSE_LINKS:-10}
ADDED=0
REPORT_FILE="$VAULT_DIR/autonomie/brain-memos/SYNAPSES_$TODAY.md"

mkdir -p "$(dirname "$LOG")" "$VAULT_DIR/autonomie/brain-memos" 2>/dev/null
log() { echo "$(date -Iseconds) $1" | tee -a "$LOG"; }

# Guards
SKIP_FILE="$LOCKFILE_DIR/synapse-skip"
[ -f "$SKIP_FILE" ] && { rm -f "$SKIP_FILE"; log "bypass"; exit 0; }

if [ -z "$RAG_SEARCH_CMD" ]; then
  log "ERROR: RAG_SEARCH_CMD not configured. Cannot build synapses without search."
  exit 1
fi

log "====== Synapse Builder Start ======"

# Strategy: Take the 20 newest vault files (last 7 days)
# and find the most similar other files for each.
# If they have no [[link]] to each other -> suggest "See also".

RECENT_FILES=$(find "$VAULT_DIR" -name "*.md" -mtime -7 -not -path "*/node_modules/*" -not -path "*/.obsidian/*" -not -name "INDEX*" | head -20)
RECENT_COUNT=$(echo "$RECENT_FILES" | grep -c '.' || echo 0)

if [ "$RECENT_COUNT" -lt 2 ]; then
  log "Too few new files ($RECENT_COUNT). Done."
  exit 0
fi

log "$RECENT_COUNT new files found"

SUGGESTIONS=""

while IFS= read -r source_file; do
  [ -z "$source_file" ] && continue
  [ $ADDED -ge $MAX_LINKS ] && break

  source_name=$(basename "$source_file" .md)
  source_rel=${source_file#$VAULT_DIR/}

  # First 3 content lines as search query
  QUERY=$(head -10 "$source_file" 2>/dev/null | grep -v "^---" | grep -v "^$" | head -3 | tr '\n' ' ')
  [ -z "$QUERY" ] && continue

  # RAG search: find most similar documents
  RESULTS=$(eval "$RAG_SEARCH_CMD" "$QUERY" 5 2>/dev/null | grep -oP '\[\d+\.\d+\] \K.*' || true)

  while IFS= read -r target_path; do
    [ -z "$target_path" ] && continue
    [ $ADDED -ge $MAX_LINKS ] && break

    target_name=$(basename "$target_path" .md)

    # Skip same file
    [ "$source_name" = "$target_name" ] && continue

    # Check if already linked
    if grep -q "\[\[$target_name\]\]\|\[\[$target_path\]\]" "$source_file" 2>/dev/null; then
      continue
    fi

    # Check if target file exists
    TARGET_FULL="$VAULT_DIR/$target_path"
    [ ! -f "$TARGET_FULL" ] && continue

    # Check if already mentioned
    if grep -q "$target_name" "$source_file" 2>/dev/null; then
      continue
    fi

    # Add "See also" section if not present
    if ! grep -q "## See also" "$source_file" 2>/dev/null; then
      echo "" >> "$source_file"
      echo "## See also" >> "$source_file"
      echo "" >> "$source_file"
    fi

    echo "- [[$target_name]] - Related topic (auto-synapse $TODAY)" >> "$source_file"
    ADDED=$((ADDED + 1))
    SUGGESTIONS="$SUGGESTIONS\n- $source_rel -> [[$target_name]]"
    log "Synapse: $source_rel -> $target_name"

  done <<< "$RESULTS"

done <<< "$RECENT_FILES"

# Write report
cat > "$REPORT_FILE" << REPORT
---
title: Synapse Report $TODAY
type: brain-synapse
date: $TODAY
connections: $ADDED
---

# Synapse Report - $TODAY

> Automatically created by brain-synapse-builder.sh
> New cross-links in the vault based on embedding similarity.

## New Connections ($ADDED)

$(echo -e "$SUGGESTIONS" | sort)

## Statistics

| Metric | Value |
|--------|-------|
| Files checked | $RECENT_COUNT |
| New connections | $ADDED |
| Date | $TODAY |

---
*Generated: $(date -Iseconds)*
REPORT

# RAG reindex if changes were made
if [ $ADDED -gt 0 ] && [ -n "$RAG_INDEX_CMD" ]; then
  log "RAG reindex ($ADDED synapses created)"
  eval "$RAG_INDEX_CMD" >> "$LOG" 2>&1 &
fi

log "====== Synapse Builder Complete: $ADDED connections ======"
