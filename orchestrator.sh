#!/bin/bash
# =============================================================================
# AUTONOMIE-OS ORCHESTRATOR
# =============================================================================
# Runs all modules in the correct order. Designed for cron or manual execution.
#
# Usage:
#   ./orchestrator.sh              # Run all modules
#   ./orchestrator.sh --nightly    # Nightly run (brain + dreaming + learning)
#   ./orchestrator.sh --weekly     # Weekly run (synapse + reflect + improve)
#   ./orchestrator.sh --module X   # Run single module
#
# Cron examples:
#   0 2 * * *   /path/to/autonomie-os/orchestrator.sh --nightly
#   0 8 * * 0   /path/to/autonomie-os/orchestrator.sh --weekly
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

LOG="$LOG_DIR/orchestrator.log"
START=$(date +%s)

log() { echo "[$(date -Iseconds)] orchestrator: $*" | tee -a "$LOG"; }

run_module() {
  local name="$1"
  local script="$2"

  if [ ! -x "$script" ]; then
    log "SKIP $name (not found or not executable: $script)"
    return 0
  fi

  log "START $name"
  local mod_start
  mod_start=$(date +%s)

  if "$script" >> "$LOG" 2>&1; then
    local duration=$(( $(date +%s) - mod_start ))
    log "OK    $name (${duration}s)"
  else
    local duration=$(( $(date +%s) - mod_start ))
    log "FAIL  $name (${duration}s, exit $?)"
  fi
}

# --- Parse arguments ---
MODE="all"
SINGLE_MODULE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nightly) MODE="nightly"; shift ;;
    --weekly)  MODE="weekly"; shift ;;
    --module)  MODE="single"; SINGLE_MODULE="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [--nightly|--weekly|--module <name>]"
      echo ""
      echo "Modules: dreaming, dreaming-local, learning-loop, learning-apply,"
      echo "         learning-consolidator, session-learner, nightly-brain,"
      echo "         brain-rag-filler, brain-synapse, eval-regression,"
      echo "         skill-auto-improve, reflect-loop"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

log "====== Orchestrator Start (mode: $MODE) ======"

# --- Module paths ---
DREAMING="$SCRIPT_DIR/modules/dreaming/dreaming.sh"
DREAMING_LOCAL="$SCRIPT_DIR/modules/dreaming/dreaming-local.sh"
LEARNING_LOOP="$SCRIPT_DIR/modules/learning/learning-loop.sh"
LEARNING_APPLY="$SCRIPT_DIR/modules/learning/learning-apply.sh"
LEARNING_CONSOLIDATOR="$SCRIPT_DIR/modules/learning/learning-consolidator.sh"
SESSION_LEARNER="$SCRIPT_DIR/modules/learning/session-learner.sh"
NIGHTLY_BRAIN="$SCRIPT_DIR/modules/brain/nightly-brain.sh"
BRAIN_RAG_FILLER="$SCRIPT_DIR/modules/brain/brain-rag-filler.sh"
BRAIN_SYNAPSE="$SCRIPT_DIR/modules/brain/brain-synapse-builder.sh"
EVAL_REGRESSION="$SCRIPT_DIR/modules/eval/eval-regression.sh"
SKILL_IMPROVE="$SCRIPT_DIR/modules/skills/skill-auto-improve.sh"
REFLECT_LOOP="$SCRIPT_DIR/modules/skills/reflect-loop.sh"

case "$MODE" in
  nightly)
    # Recommended: daily at 02:00-04:00
    #
    #   02:00  Dreaming       Analyze today's sessions, write playbooks
    #   03:00  Nightly Brain  Prioritize learnings, fill RAG gaps, find patterns
    #          (Brain internally runs: rag-filler, learning-loop, learning-apply)
    #   04:00  Eval           Check for regressions in recent bugfixes
    run_module "dreaming"        "$DREAMING"
    run_module "nightly-brain"   "$NIGHTLY_BRAIN"
    run_module "eval-regression" "$EVAL_REGRESSION"
    ;;

  weekly)
    # Recommended: Sundays at 08:00
    #
    #   08:00  Dreaming-Local   Deep local analysis (Ollama, last 7 days)
    #   08:15  Brain-Synapse    Cross-link vault documents
    #   08:30  Reflect-Loop     Find crystallization candidates
    #   09:00  Skill-Improve    Analyze and stage skill improvements
    run_module "dreaming-local"    "$DREAMING_LOCAL"
    run_module "brain-synapse"     "$BRAIN_SYNAPSE"
    run_module "reflect-loop"      "$REFLECT_LOOP"
    run_module "skill-auto-improve" "$SKILL_IMPROVE"
    ;;

  single)
    case "$SINGLE_MODULE" in
      dreaming)              run_module "$SINGLE_MODULE" "$DREAMING" ;;
      dreaming-local)        run_module "$SINGLE_MODULE" "$DREAMING_LOCAL" ;;
      learning-loop)         run_module "$SINGLE_MODULE" "$LEARNING_LOOP" ;;
      learning-apply)        run_module "$SINGLE_MODULE" "$LEARNING_APPLY" ;;
      learning-consolidator) run_module "$SINGLE_MODULE" "$LEARNING_CONSOLIDATOR" ;;
      session-learner)       run_module "$SINGLE_MODULE" "$SESSION_LEARNER" ;;
      nightly-brain)         run_module "$SINGLE_MODULE" "$NIGHTLY_BRAIN" ;;
      brain-rag-filler)      run_module "$SINGLE_MODULE" "$BRAIN_RAG_FILLER" ;;
      brain-synapse)         run_module "$SINGLE_MODULE" "$BRAIN_SYNAPSE" ;;
      eval-regression)       run_module "$SINGLE_MODULE" "$EVAL_REGRESSION" ;;
      skill-auto-improve)    run_module "$SINGLE_MODULE" "$SKILL_IMPROVE" ;;
      reflect-loop)          run_module "$SINGLE_MODULE" "$REFLECT_LOOP" ;;
      *) log "Unknown module: $SINGLE_MODULE"; exit 1 ;;
    esac
    ;;

  all)
    # Full run: all modules in dependency order
    run_module "dreaming"           "$DREAMING"
    run_module "nightly-brain"      "$NIGHTLY_BRAIN"
    run_module "eval-regression"    "$EVAL_REGRESSION"
    run_module "dreaming-local"     "$DREAMING_LOCAL"
    run_module "brain-synapse"      "$BRAIN_SYNAPSE"
    run_module "reflect-loop"       "$REFLECT_LOOP"
    run_module "skill-auto-improve" "$SKILL_IMPROVE"
    ;;
esac

DURATION=$(( $(date +%s) - START ))
log "====== Orchestrator Complete (${DURATION}s) ======"
