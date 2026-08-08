<h1 align="center">Autonomie-OS</h1>

[![Part of AgentStack](https://img.shields.io/badge/Part%20of-AgentStack-blue?style=flat-square)](https://github.com/FvdHMBAI/agent-stack)

<p align="center">
  <strong>The self-improving AI agent framework.</strong><br>
  Your agents get better overnight. Automatically. On your hardware.
</p>

<p align="center">
  <a href="https://github.com/FvdHMBAI/autonomie-os/actions"><img src="https://github.com/FvdHMBAI/autonomie-os/actions/workflows/ci.yml/badge.svg" alt="CI"></a>&nbsp;
  <a href="https://github.com/FvdHMBAI/autonomie-os/stargazers"><img src="https://img.shields.io/github/stars/FvdHMBAI/autonomie-os?style=social" alt="GitHub Stars"></a>&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

<p align="center">
  <a href="#the-crystallization-loop">How it works</a> ·
  <a href="#modules">Modules</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#how-it-compares">Comparison</a> ·
  <a href="#the-agentstack-ecosystem">Ecosystem</a>
</p>

---

## The Story

My AI agent made the same mistake three times in one week. Wrong database connection string. Same error, same fix, same wasted 20 minutes each time.

The fourth time, it caught itself.

Not because I added a rule. Because Autonomie-OS analyzed its sessions overnight, extracted the pattern, and wrote a guard for it.

**198 feedback rules exist in our production system today. None of them were written by a human.**

Most AI frameworks help agents *do things*. Autonomie-OS helps agents *become better at doing things*. It runs overnight, analyzes your agent's sessions, extracts what worked and what didn't, fills knowledge gaps, detects regressions, and proposes its own improvements.

The difference between a tool and an organism is that an organism adapts.

---

## The Crystallization Loop

This is the core idea. Every session feeds the next one:

```
    ┌──────────────────────────────────────────────────────────────┐
    │                   THE CRYSTALLIZATION LOOP                    │
    │                                                              │
    │   ┌──────────┐     ┌──────────┐     ┌──────────┐            │
    │   │ SESSION  │────▶│ ANALYSIS │────▶│ PATTERN  │            │
    │   │          │     │          │     │          │            │
    │   │ Agent    │     │ Dreaming │     │ "Same    │            │
    │   │ works,   │     │ module   │     │  error   │            │
    │   │ fails,   │     │ extracts │     │  3x this │            │
    │   │ learns   │     │ signals  │     │  week"   │            │
    │   └──────────┘     └──────────┘     └─────┬────┘            │
    │        ▲                                  │                 │
    │        │                                  ▼                 │
    │   ┌────┴─────┐                      ┌──────────┐            │
    │   │ BETTER   │                      │  RULE    │            │
    │   │ SESSION  │◀─────────────────────│          │            │
    │   │          │                      │ Guard,   │            │
    │   │ Agent    │                      │ memory,  │            │
    │   │ doesn't  │                      │ skill,   │            │
    │   │ repeat   │                      │ or vault │            │
    │   │ mistakes │                      │ entry    │            │
    │   └──────────┘                      └──────────┘            │
    │                                                              │
    └──────────────────────────────────────────────────────────────┘
```

**In production right now:**

| Metric | Count |
|--------|-------|
| Crystallized feedback rules | **198** |
| Skills with active learnings | **61** |
| Learning entries (auto-generated) | **73** |
| Autonomous tasks completed | **1,048** |
| Autonomous task success rate | **89%** |

Every number here was produced by the system itself. No manual curation.

---

<p align="center">
  <img src="demo/demo.gif" alt="Autonomie-OS Demo" width="700">
</p>

---

## Architecture

```
                          AUTONOMIE-OS
    ┌─────────────────────────────────────────────────────────┐
    │                    ORCHESTRATOR                          │
    │   Runs modules in dependency order (cron / manual)      │
    └──────┬──────────┬──────────┬──────────┬────────┬────────┘
           │          │          │          │        │
    ┌──────▼──────┐ ┌─▼────────┐ ┌▼────────┐ ┌─────▼──┐ ┌────▼─────┐
    │  DREAMING   │ │ LEARNING │ │  BRAIN  │ │  EVAL  │ │  SKILLS  │
    │             │ │          │ │         │ │        │ │          │
    │ Session     │ │ Loop     │ │ Nightly │ │ Regr.  │ │ Auto-    │
    │ Analysis    │ │ Session  │ │ RAG     │ │ Check  │ │ Improve  │
    │ Pattern     │ │ Learner  │ │ Filler  │ │ Drift  │ │ Reflect  │
    │ Detection   │ │ Consoli- │ │ Synapse │ │ Check  │ │ Loop     │
    │ Playbook    │ │ dator    │ │ Builder │ │        │ │ Crystal- │
    │ Writing     │ │ Apply    │ │         │ │        │ │ lization │
    └──────┬──────┘ └─┬────────┘ └┬────────┘ └───┬────┘ └────┬─────┘
           │          │           │              │           │
    ┌──────▼──────────▼───────────▼──────────────▼───────────▼──────┐
    │                        PostgreSQL                             │
    │  learning_items │ error_patterns │ rag_misses │ dreaming_runs │
    │  skill_proposals │ skill_decisions │ skill_metrics             │
    └──────┬──────────────────────┬─────────────────────────────────┘
           │                     │
    ┌──────▼──────┐       ┌──────▼──────┐       ┌──────────────┐
    │ Vault/Docs  │       │ Notify      │       │ CHAIN RUNNER │
    │ (Obsidian,  │       │ (ntfy.sh,   │       │ Multi-phase  │
    │  Markdown)  │       │  webhooks)  │       │ autonomous   │
    └─────────────┘       └─────────────┘       │ task runner  │
                                                └──────────────┘
```

## Modules

### Dreaming: *"What happened today?"*

Runs nightly. Analyzes session logs, detects recurring patterns, writes playbooks for common problems, and proposes new skills when the same pattern occurs 5+ times.

**Input:** Session logs, error patterns, RAG misses, git activity
**Output:** Playbooks, applied learnings, skill proposals, vault stubs

### Learning: *"What should we remember?"*

A four-stage pipeline that turns raw signals into actionable improvements:

1. **Learning Loop**: Converts RAG misses and high-frequency errors into learning items
2. **Session Learner**: Extracts key findings from session logs
3. **Consolidator**: Clusters by topic, deduplicates, generates reports
4. **Learning Apply**: LLM classifies items as guard/memory/vault/config/skip, archives noise

### Brain: *"What's missing from our knowledge?"*

Active knowledge base maintenance:

- **Nightly Brain**: Prioritizes top-5 learnings, finds cross-domain patterns, generates creative ideas
- **RAG Filler**: Creates documentation stubs for frequently missed search queries
- **Synapse Builder**: Links thematically related documents using embedding similarity

### Eval: *"Did we break something?"*

Automated quality checks:

- **Regression Detection**: Flags when a new bugfix targets the same repo and symptoms as an older fix
- **Drift Check**: Deterministic measurement of undocumented API routes and database tables (Python)

### Skills: *"How can we get better?"*

Self-optimization:

- **Skill Auto-Improve**: Collects error patterns, runs LLM triage, stages improvement proposals
- **Reflect Loop**: Scans learnings for crystallization candidates (Score >= 4 AND Runs >= 3)

### Chain Runner: *Autonomous multi-phase execution*

Runs complex tasks with safety:

- Parses markdown task definitions with phases
- Runs each phase in a fresh AI agent session
- Verification gates between phases (TypeScript, build, tests)
- Budget and time limits with automatic stop
- Retry on gate failure
- Full audit trail

---

## Quick Start

### Prerequisites

- **PostgreSQL** >= 12
- **bash** >= 4.0
- **jq**, **curl**, **bc**
- One LLM provider:
  - [Anthropic Claude](https://console.anthropic.com/) API key (recommended), or
  - [Ollama](https://ollama.ai/) running locally (free)

### Install

```bash
git clone https://github.com/FvdHMBAI/autonomie-os.git
cd autonomie-os

# Configure
cp config.sh config.local.sh
vim config.local.sh  # Set VAULT_DIR, database, LLM provider

# Install (creates DB schema, directories, suggests cron jobs)
./install.sh

# Verify
./orchestrator.sh --module dreaming
tail -f /var/log/autonomie/dreaming.log
```

### Cron Schedule

```cron
# Nightly: dreaming + brain + eval (recommended: 02:00)
0 2 * * * /path/to/autonomie-os/orchestrator.sh --nightly

# Weekly: deep analysis + synapse + skills (recommended: Sunday 08:00)
0 8 * * 0 /path/to/autonomie-os/orchestrator.sh --weekly
```

### First Dreaming Session

After a day of AI agent sessions:

```bash
./orchestrator.sh --nightly

# Check what happened
cat ~/vault/autonomie/dreaming/$(date +%Y-%m-%d).md
```

See [examples/first-dreaming-session.md](examples/first-dreaming-session.md) for sample output.

---

## How the Nightly Run Works

```
  02:00  orchestrator.sh --nightly
           │
           ├── dreaming.sh           Analyze today's sessions
           ├── nightly-brain.sh      Prioritize learnings, fill gaps
           │     ├── brain-rag-filler.sh
           │     ├── learning-loop.sh
           │     │     ├── session-learner.sh
           │     │     └── learning-consolidator.sh
           │     └── learning-apply.sh
           └── eval-regression.sh    Detect regressions

  08:00  orchestrator.sh --weekly (Sundays)
           │
           ├── dreaming-local.sh     Deep local analysis (Ollama, 7 days)
           ├── brain-synapse.sh      Cross-link vault documents
           ├── reflect-loop.sh       Find crystallization candidates
           └── skill-auto-improve.sh Stage skill improvements
```

---

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_DIR` | `~/vault` | Knowledge base directory (Obsidian, Markdown) |
| `DB_CONTAINER` | | Docker container name for PostgreSQL |
| `DB_NAME` | `autonomie` | Database name |
| `ANTHROPIC_API_KEY` | | Claude API key (primary LLM) |
| `OLLAMA_URL` | `http://localhost:11434` | Ollama endpoint (fallback LLM) |
| `OLLAMA_MODEL` | `qwen3:8b` | Local model for analysis |
| `NTFY_URL` | | Push notification endpoint |
| `MONITORED_REPOS` | | Comma-separated repo paths for git analysis |
| `RAG_INDEX_CMD` | | Command to rebuild RAG index |
| `RAG_SEARCH_CMD` | | Command to search RAG index |
| `MAX_COST_PER_RUN` | `2.00` | Max API cost per orchestrator run (USD) |
| `MAX_STUBS_PER_RUN` | `5` | Max vault stubs created per RAG filler run |
| `MAX_AUTO_FIXES_PER_DAY` | `3` | Daily limit for autonomous skill improvements |
| `CHAIN_MAX_BUDGET` | `10.00` | Max budget per chain runner task (USD) |
| `CHAIN_MAX_HOURS` | `8` | Max duration per chain runner task |

---

## Database Schema

Autonomie-OS stores all learning data in PostgreSQL. See [schema.sql](schema.sql) for the full schema.

| Table | Purpose |
|-------|---------|
| `learning_items` | Improvement suggestions from all sources |
| `error_patterns` | Recurring problems with root causes and mitigations |
| `rag_misses` | Search queries that returned no results |
| `dreaming_runs` | Audit trail for nightly dreaming sessions |
| `skill_proposals` | Proposed skill improvements |
| `skill_decisions` | Judge decisions on proposals |
| `skill_metrics` | Invocation and success tracking |

---

## Examples

- [First Dreaming Session](examples/first-dreaming-session.md): What a dreaming cycle produces
- [Learning Loop Output](examples/learning-loop-output.md): How raw signals become actions
- [Eval Regression Report](examples/eval-regression-report.md): Detecting recurring bugs
- [Chain Runner Task](examples/task-template.md): Multi-phase task definition

---

## How It Compares

Most AI agent frameworks help agents do things. Autonomie-OS helps agents get better at doing things: automatically, between sessions, without human intervention.

| | Autonomie-OS | LangChain Memory | AutoGPT | BabyAGI | CrewAI |
|---|---|---|---|---|---|
| **Learns from sessions** | Yes (nightly extraction) | No | No | No | No |
| **Self-improving skills** | Yes (crystallization loop) | No | No | No | No |
| **Overnight analysis** | Yes (dreaming cycle) | No | No | No | No |
| **Detects regressions** | Yes (eval framework) | No | No | No | No |
| **Persistent memory** | Vault + PostgreSQL | Vector store | File-based | File-based | Short-term |
| **Needs human input** | No (autonomous) | No | Yes (goals) | Yes (goals) | Yes (crew config) |
| **Cross-session context** | Yes (RAG + learnings DB) | Partial (retrieval) | No | No | No |
| **Multi-agent** | No (single agent focus) | Yes (chains) | Yes | No | Yes (crews) |
| **Task execution** | Not the focus | Yes | Yes | Yes | Yes |
| **Dependencies** | bash + PostgreSQL | Python + ML stack | Python + many | Python + many | Python + many |

**They solve different problems.** LangChain, AutoGPT, and CrewAI focus on what agents do during a session. Autonomie-OS focuses on what happens between sessions: extracting learnings, detecting regressions, improving skills. Use them together: CrewAI for task execution, Autonomie-OS for continuous improvement.

---

## The AgentStack Ecosystem

Autonomie-OS is the brain of a five-tool governance stack. Each tool handles one concern. Together they form a complete operating system for AI agents:

| Tool | What it does | How Autonomie-OS connects |
|------|-------------|--------------------------|
| [**GuardRail**](https://github.com/FvdHMBAI/guardrail) | Pre-execution security guards | Autonomie-OS proposes new guards from error patterns |
| [**Model Router**](https://github.com/FvdHMBAI/model-router) | LLM routing (tiers, fallback, cost tracking) | Autonomie-OS tunes tier assignments based on task success rates |
| [**Night Shift**](https://github.com/FvdHMBAI/nightshift) | Overnight code improvement | Runs alongside Autonomie-OS in the nightly cycle |
| [**Graphify Toolkit**](https://github.com/FvdHMBAI/graphify-toolkit) | Codebase knowledge graphs | Powers impact analysis for skill proposals |

All five tools are free, open source, and run on your own hardware.

---

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Areas where help is needed

- **Additional LLM providers**: Add support for OpenAI, Gemini, Mistral
- **Alternative databases**: SQLite adapter for simpler setups
- **Visualization**: Dashboard for learning progress and pattern trends
- **Integration tests**: More coverage for edge cases

---

## Learn More

- **Free course**: [KI-Governance in 18 Lektionen](https://lernen.promptandbuild.de) (German)
- **The book**: *Runs Without Me* (coming soon)
- **Website**: [promptandbuild.de](https://promptandbuild.de)

---

## License

[MIT](LICENSE): Use it however you want.

---

<p align="center">
  Built by <a href="https://promptandbuild.de">Prompt & Build</a>.<br>
  Part of <a href="https://github.com/FvdHMBAI/agent-stack">AgentStack</a>: the complete governance layer for AI agents.
</p>

<p align="center">
  If Autonomie-OS helps your agents improve, consider giving it a <a href="https://github.com/FvdHMBAI/autonomie-os">star</a>. It helps others find it.
</p>
