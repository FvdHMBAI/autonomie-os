#!/bin/bash
# Autonomie-OS Demo Recording Script
# Simulates a nightly self-improvement run.
# Usage: asciinema rec --command "bash demo/record-demo.sh" demo.cast

set -e

G=$'\033[0;32m' R=$'\033[0;31m' Y=$'\033[0;33m' B=$'\033[1m' D=$'\033[2m' Z=$'\033[0m' C=$'\033[0;36m'

type_cmd() {
  local cmd="$1"
  printf "${D}\$ ${Z}"
  for ((i=0; i<${#cmd}; i++)); do
    printf "%s" "${cmd:$i:1}"
    sleep 0.03
  done
  echo ""
}

clear
echo ""
echo "  ${B}Autonomie-OS${Z} ${D}v1.0${Z}"
echo "  ${D}Self-improving AI agent framework${Z}"
echo ""
sleep 1

type_cmd "autonomie nightly --analyze"
sleep 0.5

echo ""
echo "  ${C}Scanning 47 sessions from today...${Z}"
sleep 0.8
echo ""
echo "  ${B}Phase 1: Extract Learnings${Z}"
sleep 0.5

echo "  ${G}+${Z} ${B}Learning 1:${Z} TypeScript strict mode catches 12% more bugs"
echo "    ${D}Evidence: 3 sessions fixed type errors that eslint missed${Z}"
sleep 0.6
echo "  ${G}+${Z} ${B}Learning 2:${Z} Running tests before commit saves 23min avg"
echo "    ${D}Evidence: 5 sessions had post-commit test failures${Z}"
sleep 0.6
echo "  ${G}+${Z} ${B}Learning 3:${Z} API routes need auth check in middleware, not handler"
echo "    ${D}Evidence: 2 sessions added auth after security review flagged it${Z}"
sleep 0.8

echo ""
echo "  ${B}Phase 2: Write to Memory${Z}"
sleep 0.5
echo "  ${G}+${Z} Wrote 3 learnings to ${D}~/.claude/memory/${Z}"
echo "  ${G}+${Z} Updated skill: ${D}quality-gate${Z} (added pre-commit test rule)"
echo "  ${G}+${Z} Created guard: ${D}auth-middleware-check${Z}"
sleep 0.8

echo ""
echo "  ${B}Phase 3: Regression Check${Z}"
sleep 0.5
echo "  ${G}+${Z} 12 existing learnings still valid"
echo "  ${Y}~${Z} 1 learning outdated (removed: ${D}node 16 workaround${Z})"
echo "  ${G}+${Z} No regressions detected"
sleep 0.8

echo ""
echo "  ${G}${B}Nightly complete:${Z} 3 new learnings, 1 outdated removed"
echo "  ${D}Your agent is now smarter than yesterday.${Z}"
echo ""
sleep 3
