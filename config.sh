#!/bin/bash
# =============================================================================
# AUTONOMIE-OS CONFIGURATION
# =============================================================================
# Central configuration for all modules. Copy this file to config.local.sh
# and adjust values to match your environment. config.local.sh is gitignored.
# =============================================================================

# --- Paths ---
AUTONOMIE_HOME="${AUTONOMIE_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
VAULT_DIR="${VAULT_DIR:-$HOME/vault}"
SESSIONS_DIR="${SESSIONS_DIR:-$VAULT_DIR/sessions}"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.agent/skills}"
LOG_DIR="${LOG_DIR:-/var/log/autonomie}"
STAGING_DIR="${STAGING_DIR:-$AUTONOMIE_HOME/staging}"

# --- Database ---
# Autonomie-OS stores learning data in PostgreSQL. Configure access here.
# Option 1: Docker container (set DB_CONTAINER)
# Option 2: Direct connection (set DB_HOST, DB_PORT, DB_USER)
DB_CONTAINER="${DB_CONTAINER:-}"
DB_NAME="${DB_NAME:-autonomie}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"

# --- LLM Providers ---
# Primary: Anthropic Claude API (recommended for best results)
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-sonnet-4-20250514}"

# Fallback: Local Ollama (free, runs on CPU/GPU)
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3:8b}"
OLLAMA_EMBEDDING_MODEL="${OLLAMA_EMBEDDING_MODEL:-nomic-embed-text}"

# --- RAG / Knowledge Base ---
# Path to your RAG index builder and search script
RAG_INDEX_CMD="${RAG_INDEX_CMD:-}"      # e.g. "node /path/to/build-index.js"
RAG_SEARCH_CMD="${RAG_SEARCH_CMD:-}"    # e.g. "node /path/to/search.js"

# --- Notifications ---
# Supports ntfy.sh (self-hosted or cloud)
NTFY_URL="${NTFY_URL:-}"                # e.g. "https://ntfy.sh/my-topic"

# --- Agent CLI ---
# Path to Claude Code CLI (used by chain-runner for autonomous phases)
AGENT_CLI="${AGENT_CLI:-claude}"
AGENT_MODEL="${AGENT_MODEL:-sonnet}"

# --- Budgets & Limits ---
MAX_COST_PER_RUN="${MAX_COST_PER_RUN:-2.00}"
MAX_STUBS_PER_RUN="${MAX_STUBS_PER_RUN:-5}"
MAX_SYNAPSE_LINKS="${MAX_SYNAPSE_LINKS:-10}"
MAX_AUTO_FIXES_PER_DAY="${MAX_AUTO_FIXES_PER_DAY:-3}"
CHAIN_MAX_BUDGET="${CHAIN_MAX_BUDGET:-10.00}"
CHAIN_MAX_HOURS="${CHAIN_MAX_HOURS:-8}"

# --- Git Repos (for drift-check and eval-regression) ---
# Comma-separated list of repo paths to monitor
MONITORED_REPOS="${MONITORED_REPOS:-}"  # e.g. "/home/dev/app1,/home/dev/app2"

# --- Cockpit DB (for eval-regression, optional) ---
COCKPIT_DB="${COCKPIT_DB:-}"            # Set if you use a task management DB

# =============================================================================
# INTERNAL (do not modify unless you know what you are doing)
# =============================================================================
LOCKFILE_DIR="${LOCKFILE_DIR:-/tmp/autonomie}"
OLLAMA_LOCK="$LOCKFILE_DIR/ollama.lock"

# Load local overrides
if [ -f "$AUTONOMIE_HOME/config.local.sh" ]; then
  # shellcheck source=/dev/null
  source "$AUTONOMIE_HOME/config.local.sh"
fi

# Ensure directories exist
mkdir -p "$LOG_DIR" "$LOCKFILE_DIR" "$STAGING_DIR" 2>/dev/null || true

# =============================================================================
# HELPER FUNCTIONS (sourced by all modules)
# =============================================================================

autonomie_log() {
  local module="${1:-autonomie}"
  shift
  echo "[$(date -Iseconds)] $module: $*" >> "$LOG_DIR/${module}.log"
}

autonomie_notify() {
  local title="$1" msg="$2" priority="${3:-default}"
  [ -z "$NTFY_URL" ] && return 0
  curl -s -H "Title: $title" -H "Priority: $priority" -H "Tags: robot" \
    -d "$msg" "$NTFY_URL" > /dev/null 2>&1 || true
}

# Database query helper
# Usage: autonomie_db "SELECT 1;"
autonomie_db() {
  local query="$1"
  if [ -n "$DB_CONTAINER" ]; then
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "$query" 2>/dev/null
  else
    PGPASSWORD="${DB_PASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "$query" 2>/dev/null
  fi
}

# Database execute (for INSERT/UPDATE, logs errors)
autonomie_db_exec() {
  local query="$1"
  local log_file="${2:-$LOG_DIR/db.log}"
  if [ -n "$DB_CONTAINER" ]; then
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$query" >> "$log_file" 2>&1
  else
    PGPASSWORD="${DB_PASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$query" >> "$log_file" 2>&1
  fi
}

# LLM query helper: tries Anthropic first, then Ollama
# Usage: autonomie_llm "prompt" [max_tokens] [temperature]
autonomie_llm() {
  local prompt="$1"
  local max_tokens="${2:-1024}"
  local temperature="${3:-0.4}"
  local result=""

  if [ -n "$ANTHROPIC_API_KEY" ]; then
    local body
    body=$(jq -n \
      --arg model "$ANTHROPIC_MODEL" \
      --argjson max_tokens "$max_tokens" \
      --arg prompt "$prompt" \
      '{model: $model, max_tokens: $max_tokens, messages: [{role: "user", content: $prompt}]}')
    result=$(curl -s --max-time 120 "https://api.anthropic.com/v1/messages" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$body" 2>/dev/null)

    local api_err
    api_err=$(printf '%s' "$result" | jq -r '.error.message // empty' 2>/dev/null)
    if [ -n "$api_err" ]; then
      autonomie_log "llm" "Anthropic error: $api_err"
      result=""
    else
      result=$(printf '%s' "$result" | jq -r '[.content[]? | select(.type=="text") | .text] | join("\n")' 2>/dev/null)
    fi
  fi

  if [ -z "$result" ] && curl -sf "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
    local body
    body=$(jq -n \
      --arg model "$OLLAMA_MODEL" \
      --arg prompt "$prompt" \
      --argjson num_predict "$max_tokens" \
      --argjson temperature "$temperature" \
      '{model: $model, prompt: $prompt, stream: false, options: {num_predict: $num_predict, temperature: $temperature}}')
    result=$(curl -s --max-time 300 "$OLLAMA_URL/api/generate" \
      -d "$body" 2>/dev/null | jq -r '.response // empty' 2>/dev/null)
  fi

  if [ -z "$result" ]; then
    echo "LLM query failed (neither Anthropic nor Ollama returned a result)"
    return 1
  fi
  echo "$result"
}
