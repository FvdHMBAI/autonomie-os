#!/bin/bash
# =============================================================================
# AUTONOMIE-OS TEST SUITE
# =============================================================================
# Validates config parsing, module loading, orchestrator lifecycle,
# SQL schema syntax, and chain-runner execution.
#
# Usage:
#   ./tests/test-autonomie.sh          # Run all tests
#   ./tests/test-autonomie.sh -v       # Verbose output
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERBOSE="${1:-}"

PASS=0
FAIL=0
SKIP=0
ERRORS=""

# --- Test helpers ---

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    [ "$VERBOSE" = "-v" ] && echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $test_name (expected '$expected', got '$actual')"
    echo "  FAIL: $test_name (expected '$expected', got '$actual')"
  fi
}

assert_ok() {
  local test_name="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    PASS=$((PASS + 1))
    [ "$VERBOSE" = "-v" ] && echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $test_name (command failed: $*)"
    echo "  FAIL: $test_name (command failed: $*)"
  fi
}

assert_fail() {
  local test_name="$1"
  shift
  if ! "$@" > /dev/null 2>&1; then
    PASS=$((PASS + 1))
    [ "$VERBOSE" = "-v" ] && echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $test_name (expected failure but succeeded)"
    echo "  FAIL: $test_name (expected failure but succeeded)"
  fi
}

assert_file_exists() {
  local test_name="$1" path="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1))
    [ "$VERBOSE" = "-v" ] && echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $test_name (file not found: $path)"
    echo "  FAIL: $test_name (file not found: $path)"
  fi
}

assert_contains() {
  local test_name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    [ "$VERBOSE" = "-v" ] && echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $test_name (does not contain '$needle')"
    echo "  FAIL: $test_name (does not contain '$needle')"
  fi
}

assert_not_contains() {
  local test_name="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    [ "$VERBOSE" = "-v" ] && echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $test_name (unexpectedly contains '$needle')"
    echo "  FAIL: $test_name (unexpectedly contains '$needle')"
  fi
}

skip_test() {
  local test_name="$1" reason="$2"
  SKIP=$((SKIP + 1))
  [ "$VERBOSE" = "-v" ] && echo "  SKIP: $test_name ($reason)"
}

echo "=== Autonomie-OS Test Suite ==="
echo ""

# =============================================================================
# 1. CONFIG PARSING
# =============================================================================
echo "--- Config Parsing ---"

# Test default values load correctly
(
  unset VAULT_DIR DB_CONTAINER ANTHROPIC_API_KEY OLLAMA_URL 2>/dev/null || true
  export AUTONOMIE_HOME="$ROOT_DIR"
  source "$ROOT_DIR/config.sh"

  assert_eq "AUTONOMIE_HOME is set" "$ROOT_DIR" "$AUTONOMIE_HOME"
  assert_eq "VAULT_DIR defaults to \$HOME/vault" "$HOME/vault" "$VAULT_DIR"
  assert_eq "DB_NAME defaults to autonomie" "autonomie" "$DB_NAME"
  assert_eq "DB_PORT defaults to 5432" "5432" "$DB_PORT"
  assert_eq "DB_USER defaults to postgres" "postgres" "$DB_USER"
  assert_eq "OLLAMA_URL defaults to localhost" "http://localhost:11434" "$OLLAMA_URL"
  assert_eq "OLLAMA_MODEL defaults to qwen3:8b" "qwen3:8b" "$OLLAMA_MODEL"
  assert_eq "MAX_COST_PER_RUN defaults to 2.00" "2.00" "$MAX_COST_PER_RUN"
  assert_eq "MAX_STUBS_PER_RUN defaults to 5" "5" "$MAX_STUBS_PER_RUN"
  assert_eq "CHAIN_MAX_BUDGET defaults to 10.00" "10.00" "$CHAIN_MAX_BUDGET"
  assert_eq "CHAIN_MAX_HOURS defaults to 8" "8" "$CHAIN_MAX_HOURS"
)

# Test config override via environment
(
  export VAULT_DIR="/tmp/test-vault"
  export DB_NAME="test_db"
  export AUTONOMIE_HOME="$ROOT_DIR"
  source "$ROOT_DIR/config.sh"

  assert_eq "VAULT_DIR override works" "/tmp/test-vault" "$VAULT_DIR"
  assert_eq "DB_NAME override works" "test_db" "$DB_NAME"
)

# Test helper functions exist
(
  export AUTONOMIE_HOME="$ROOT_DIR"
  source "$ROOT_DIR/config.sh"

  assert_ok "autonomie_log function exists" type autonomie_log
  assert_ok "autonomie_notify function exists" type autonomie_notify
  assert_ok "autonomie_db function exists" type autonomie_db
  assert_ok "autonomie_db_exec function exists" type autonomie_db_exec
  assert_ok "autonomie_llm function exists" type autonomie_llm
)

echo ""

# =============================================================================
# 2. MODULE LOADING
# =============================================================================
echo "--- Module Loading ---"

MODULES=(
  "modules/dreaming/dreaming.sh"
  "modules/dreaming/dreaming-local.sh"
  "modules/brain/nightly-brain.sh"
  "modules/brain/brain-rag-filler.sh"
  "modules/brain/brain-synapse-builder.sh"
  "modules/learning/learning-loop.sh"
  "modules/learning/learning-apply.sh"
  "modules/learning/learning-consolidator.sh"
  "modules/learning/session-learner.sh"
  "modules/eval/eval-regression.sh"
  "modules/eval/drift-check.py"
  "modules/skills/reflect-loop.sh"
  "modules/skills/skill-auto-improve.sh"
)

for mod in "${MODULES[@]}"; do
  assert_file_exists "Module exists: $mod" "$ROOT_DIR/$mod"
done

# Check all shell modules are executable
for mod in "${MODULES[@]}"; do
  if [[ "$mod" == *.sh ]]; then
    if [ -x "$ROOT_DIR/$mod" ]; then
      PASS=$((PASS + 1))
      [ "$VERBOSE" = "-v" ] && echo "  PASS: Executable: $mod"
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL: Not executable: $mod"
    fi
  fi
done

# Check all shell scripts have valid shebang
for mod in "${MODULES[@]}"; do
  if [[ "$mod" == *.sh ]]; then
    SHEBANG=$(head -1 "$ROOT_DIR/$mod")
    if echo "$SHEBANG" | grep -qE '^#!/(usr/)?bin/(env )?bash'; then
      PASS=$((PASS + 1))
      [ "$VERBOSE" = "-v" ] && echo "  PASS: Valid shebang: $mod"
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL: Invalid shebang in $mod: $SHEBANG"
    fi
  fi
done

echo ""

# =============================================================================
# 3. ORCHESTRATOR LIFECYCLE
# =============================================================================
echo "--- Orchestrator Lifecycle ---"

# Test --help works
HELP_OUTPUT=$(bash "$ROOT_DIR/orchestrator.sh" --help 2>&1)
assert_contains "orchestrator --help shows usage" "$HELP_OUTPUT" "Usage:"
assert_contains "orchestrator --help lists modules" "$HELP_OUTPUT" "dreaming"
assert_contains "orchestrator --help lists nightly" "$HELP_OUTPUT" "nightly"
assert_contains "orchestrator --help lists weekly" "$HELP_OUTPUT" "weekly"

# Test unknown option fails
assert_fail "orchestrator rejects unknown option" bash "$ROOT_DIR/orchestrator.sh" --invalid-option

echo ""

# =============================================================================
# 4. SQL SCHEMA VALIDATION
# =============================================================================
echo "--- SQL Schema Validation ---"

SCHEMA="$ROOT_DIR/schema.sql"

assert_file_exists "schema.sql exists" "$SCHEMA"

# Check required tables
SCHEMA_CONTENT=$(cat "$SCHEMA")
assert_contains "Schema has learning_items table" "$SCHEMA_CONTENT" "CREATE TABLE IF NOT EXISTS learning_items"
assert_contains "Schema has error_patterns table" "$SCHEMA_CONTENT" "CREATE TABLE IF NOT EXISTS error_patterns"
assert_contains "Schema has rag_misses table" "$SCHEMA_CONTENT" "CREATE TABLE IF NOT EXISTS rag_misses"
assert_contains "Schema has dreaming_runs table" "$SCHEMA_CONTENT" "CREATE TABLE IF NOT EXISTS dreaming_runs"
assert_contains "Schema has skill_proposals table" "$SCHEMA_CONTENT" "CREATE TABLE IF NOT EXISTS skill_proposals"
assert_contains "Schema has skill_decisions table" "$SCHEMA_CONTENT" "CREATE TABLE IF NOT EXISTS skill_decisions"
assert_contains "Schema has skill_metrics table" "$SCHEMA_CONTENT" "CREATE TABLE IF NOT EXISTS skill_metrics"

# Check indexes
assert_contains "Schema has learning_items index" "$SCHEMA_CONTENT" "idx_learning_items_applied"
assert_contains "Schema has error_patterns index" "$SCHEMA_CONTENT" "idx_error_patterns_resolved"
assert_contains "Schema has rag_misses index" "$SCHEMA_CONTENT" "idx_rag_misses_resolved"
assert_contains "Schema has dreaming_runs index" "$SCHEMA_CONTENT" "idx_dreaming_runs_date"

# Check SQL syntax (basic: no unclosed parens, balanced quotes)
OPEN_PARENS=$(echo "$SCHEMA_CONTENT" | tr -cd '(' | wc -c)
CLOSE_PARENS=$(echo "$SCHEMA_CONTENT" | tr -cd ')' | wc -c)
assert_eq "SQL has balanced parentheses" "$OPEN_PARENS" "$CLOSE_PARENS"

echo ""

# =============================================================================
# 5. CHAIN RUNNER VALIDATION
# =============================================================================
echo "--- Chain Runner ---"

RUNNER="$ROOT_DIR/chain-runner.sh"
assert_file_exists "chain-runner.sh exists" "$RUNNER"

# Test missing argument
RUNNER_NO_ARG=$(bash "$RUNNER" 2>&1 || true)
assert_contains "chain-runner shows usage without args" "$RUNNER_NO_ARG" "Usage:"

# Test --dry-run with example task
EXAMPLE_TASK="$ROOT_DIR/examples/task-template.md"
if [ -f "$EXAMPLE_TASK" ]; then
  DRY_OUTPUT=$(bash "$RUNNER" --dry-run "$EXAMPLE_TASK" 2>&1 || true)
  assert_contains "chain-runner --dry-run parses task" "$DRY_OUTPUT" "Task:"
  assert_contains "chain-runner --dry-run shows budget" "$DRY_OUTPUT" "Budget"
else
  skip_test "chain-runner --dry-run" "example task template not found"
fi

echo ""

# =============================================================================
# 6. DRIFT CHECK (Python)
# =============================================================================
echo "--- Drift Check ---"

DRIFT="$ROOT_DIR/modules/eval/drift-check.py"
assert_file_exists "drift-check.py exists" "$DRIFT"

if command -v python3 > /dev/null 2>&1; then
  # Test syntax
  assert_ok "drift-check.py has valid Python syntax" python3 -c "import py_compile; py_compile.compile('$DRIFT', doraise=True)"

  # Test import
  assert_ok "drift-check.py imports successfully" python3 -c "import importlib.util; spec = importlib.util.spec_from_file_location('drift', '$DRIFT'); mod = importlib.util.module_from_spec(spec)"

  # Test --json flag with empty config
  DRIFT_OUTPUT=$(AUTONOMIE_DRIFT_CONFIG=/dev/null python3 "$DRIFT" --json 2>/dev/null || echo '{}')
  assert_contains "drift-check outputs JSON" "$DRIFT_OUTPUT" "missing_total"
else
  skip_test "drift-check.py syntax" "python3 not available"
  skip_test "drift-check.py import" "python3 not available"
  skip_test "drift-check.py --json" "python3 not available"
fi

echo ""

# =============================================================================
# 7. SANITIZATION CHECK
# =============================================================================
echo "--- Sanitization ---"

ALL_CODE=$(find "$ROOT_DIR" -not -path '*/.git/*' -not -path '*/tests/*' -type f \( -name '*.sh' -o -name '*.py' -o -name '*.sql' \) -exec cat {} +)
assert_not_contains "No /opt/scripts paths" "$ALL_CODE" "/opt/scripts"
assert_not_contains "No /opt/obsidian paths" "$ALL_CODE" "/opt/obsidian-vault"
assert_not_contains "No hardcoded IPs" "$ALL_CODE" "88.99.82"

echo ""

# =============================================================================
# 8. INSTALL SCRIPT
# =============================================================================
echo "--- Install Script ---"

INSTALLER="$ROOT_DIR/install.sh"
assert_file_exists "install.sh exists" "$INSTALLER"

INSTALL_CONTENT=$(cat "$INSTALLER")
assert_contains "Installer references config.local.sh" "$INSTALL_CONTENT" "config.local.sh"
assert_contains "Installer creates DB schema" "$INSTALL_CONTENT" "CREATE TABLE"
assert_contains "Installer sets permissions" "$INSTALL_CONTENT" "chmod"

echo ""

# =============================================================================
# SUMMARY
# =============================================================================
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "FAILURES:"
  echo -e "$ERRORS"
  echo ""
  exit 1
else
  echo "All tests passed."
  exit 0
fi
