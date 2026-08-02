#!/bin/bash
# =============================================================================
# AUTONOMIE-OS INSTALLER
# =============================================================================
# Sets up the database schema, directory structure, and cron jobs.
#
# Usage:
#   ./install.sh              # Interactive setup
#   ./install.sh --db-only    # Only create database tables
#   ./install.sh --cron-only  # Only install cron jobs
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  Autonomie-OS Installer"
echo "========================================"
echo ""

# --- Check config ---
if [ ! -f "$SCRIPT_DIR/config.local.sh" ]; then
  echo "No config.local.sh found. Creating from template..."
  cp "$SCRIPT_DIR/config.sh" "$SCRIPT_DIR/config.local.sh"
  echo ""
  echo "IMPORTANT: Edit config.local.sh before continuing!"
  echo "At minimum, set:"
  echo "  - VAULT_DIR (path to your knowledge vault)"
  echo "  - DB_CONTAINER or DB_HOST (PostgreSQL connection)"
  echo "  - ANTHROPIC_API_KEY or ensure Ollama is running"
  echo ""
  echo "Then run ./install.sh again."
  exit 0
fi

# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

MODE="${1:-all}"

# --- Database setup ---
setup_database() {
  echo "Setting up database schema..."

  SQL="
  -- Autonomie-OS Schema
  CREATE TABLE IF NOT EXISTS learning_items (
    id SERIAL PRIMARY KEY,
    source VARCHAR(50) NOT NULL DEFAULT 'manual',
    lesson TEXT NOT NULL,
    applicable_to VARCHAR(200),
    occurrence_count INTEGER DEFAULT 1,
    applied BOOLEAN DEFAULT false,
    applied_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE IF NOT EXISTS error_patterns (
    id SERIAL PRIMARY KEY,
    pattern_key VARCHAR(100) NOT NULL UNIQUE,
    category VARCHAR(50),
    description TEXT,
    root_cause TEXT,
    mitigation TEXT,
    related_skill VARCHAR(100),
    occurrence_count INTEGER DEFAULT 1,
    resolved BOOLEAN DEFAULT false,
    addressed BOOLEAN DEFAULT false,
    last_seen TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE IF NOT EXISTS rag_misses (
    id SERIAL PRIMARY KEY,
    query TEXT NOT NULL,
    resolved BOOLEAN DEFAULT false,
    resolved_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE IF NOT EXISTS dreaming_runs (
    id SERIAL PRIMARY KEY,
    run_date DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    sessions_analyzed INTEGER DEFAULT 0,
    learnings_applied INTEGER DEFAULT 0,
    patterns_updated INTEGER DEFAULT 0,
    playbooks_created INTEGER DEFAULT 0,
    skill_proposals_created INTEGER DEFAULT 0,
    rag_gaps_filled INTEGER DEFAULT 0,
    vault_report_path TEXT,
    duration_seconds INTEGER,
    cost_usd NUMERIC(8,4) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE IF NOT EXISTS skill_proposals (
    id SERIAL PRIMARY KEY,
    proposal_type VARCHAR(50) NOT NULL,
    target_skill VARCHAR(200),
    proposal_content TEXT,
    recurrence_count INTEGER DEFAULT 0,
    confidence INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE IF NOT EXISTS skill_decisions (
    id SERIAL PRIMARY KEY,
    skill_name VARCHAR(200),
    decision_type VARCHAR(50),
    judge_decision TEXT,
    was_applied BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE IF NOT EXISTS skill_metrics (
    id SERIAL PRIMARY KEY,
    skill_name VARCHAR(200) NOT NULL,
    invoked BOOLEAN DEFAULT true,
    success BOOLEAN DEFAULT true,
    duration_minutes NUMERIC(8,2),
    created_at TIMESTAMP DEFAULT NOW()
  );

  CREATE INDEX IF NOT EXISTS idx_learning_items_applied ON learning_items(applied);
  CREATE INDEX IF NOT EXISTS idx_error_patterns_resolved ON error_patterns(resolved);
  CREATE INDEX IF NOT EXISTS idx_rag_misses_resolved ON rag_misses(resolved);
  CREATE INDEX IF NOT EXISTS idx_dreaming_runs_date ON dreaming_runs(run_date);
  CREATE INDEX IF NOT EXISTS idx_skill_metrics_name ON skill_metrics(skill_name);
  "

  if [ -n "$DB_CONTAINER" ]; then
    echo "$SQL" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" 2>&1
  else
    echo "$SQL" | PGPASSWORD="${DB_PASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" 2>&1
  fi

  echo "Database schema created."
}

# --- Directory setup ---
setup_directories() {
  echo "Creating directory structure..."

  mkdir -p "$VAULT_DIR/autonomie/dreaming"
  mkdir -p "$VAULT_DIR/autonomie/brain-memos"
  mkdir -p "$VAULT_DIR/autonomie/learning-actions"
  mkdir -p "$VAULT_DIR/autonomie/skill-evolution"
  mkdir -p "$VAULT_DIR/autonomie/chain-runs"
  mkdir -p "$VAULT_DIR/playbooks"
  mkdir -p "$VAULT_DIR/known-issues"
  mkdir -p "$VAULT_DIR/sessions"
  mkdir -p "$LOG_DIR"
  mkdir -p "$STAGING_DIR"
  mkdir -p "$LOCKFILE_DIR"

  echo "Directories created."
}

# --- Make scripts executable ---
setup_permissions() {
  echo "Setting permissions..."
  find "$SCRIPT_DIR" -name "*.sh" -exec chmod +x {} \;
  chmod +x "$SCRIPT_DIR/modules/eval/drift-check.py" 2>/dev/null || true
  echo "Permissions set."
}

# --- Cron setup ---
setup_cron() {
  echo ""
  echo "Suggested cron entries (add with 'crontab -e'):"
  echo ""
  echo "# Autonomie-OS: Nightly run (dreaming + brain + eval)"
  echo "0 2 * * * $SCRIPT_DIR/orchestrator.sh --nightly >> $LOG_DIR/cron.log 2>&1"
  echo ""
  echo "# Autonomie-OS: Weekly run (synapse + reflect + skill-improve)"
  echo "0 8 * * 0 $SCRIPT_DIR/orchestrator.sh --weekly >> $LOG_DIR/cron.log 2>&1"
  echo ""

  read -p "Install these cron jobs now? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    (crontab -l 2>/dev/null | grep -v "autonomie-os"; echo "# Autonomie-OS
0 2 * * * $SCRIPT_DIR/orchestrator.sh --nightly >> $LOG_DIR/cron.log 2>&1
0 8 * * 0 $SCRIPT_DIR/orchestrator.sh --weekly >> $LOG_DIR/cron.log 2>&1") | crontab -
    echo "Cron jobs installed."
  else
    echo "Skipped. Add manually when ready."
  fi
}

# --- Verify ---
verify() {
  echo ""
  echo "Verification:"

  # Check database
  RESULT=$(autonomie_db "SELECT COUNT(*) FROM learning_items;" 2>/dev/null || echo "FAIL")
  if [ "$RESULT" = "FAIL" ]; then
    echo "  [FAIL] Database connection"
  else
    echo "  [OK]   Database connection ($RESULT learning items)"
  fi

  # Check LLM
  if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "  [OK]   Anthropic API key configured"
  else
    echo "  [WARN] No Anthropic API key (will use Ollama fallback)"
  fi

  if curl -s --max-time 3 "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
    echo "  [OK]   Ollama reachable at $OLLAMA_URL"
  else
    echo "  [WARN] Ollama not reachable at $OLLAMA_URL"
  fi

  # Check vault
  if [ -d "$VAULT_DIR" ]; then
    echo "  [OK]   Vault directory exists: $VAULT_DIR"
  else
    echo "  [FAIL] Vault directory not found: $VAULT_DIR"
  fi

  echo ""
}

# --- Run ---
case "$MODE" in
  --db-only)
    setup_database
    ;;
  --cron-only)
    setup_cron
    ;;
  all|*)
    setup_directories
    setup_permissions
    setup_database
    setup_cron
    verify
    echo "Autonomie-OS installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit config.local.sh with your settings"
    echo "  2. Run: ./orchestrator.sh --nightly  (test nightly run)"
    echo "  3. Check logs: tail -f $LOG_DIR/orchestrator.log"
    ;;
esac
