# Autonomie-OS

**Self-improving AI agent framework: dreaming, learning loops, nightly brain maintenance, and evaluation regression testing.**

Autonomie-OS is a production-tested framework that makes AI agents learn from their own sessions. Instead of repeating the same mistakes, your agents dream about what happened, extract lessons, fill knowledge gaps, and propose their own improvements.

```
                          AUTONOMIE-OS ARCHITECTURE
    
    +------------------+     +------------------+     +------------------+
    |    DREAMING       |     |    LEARNING       |     |      BRAIN       |
    |                   |     |                   |     |                  |
    | Session Analysis  |     | Learning Loop     |     | Nightly Brain    |
    | Pattern Detection |---->| Session Learner   |---->| RAG Filler       |
    | Playbook Writing  |     | Consolidator      |     | Synapse Builder  |
    | Skill Proposals   |     | Learning Apply    |     | Drift Check      |
    +--------+----------+     +--------+----------+     +--------+---------+
             |                         |                         |
             v                         v                         v
    +--------+-------------------------+-------------------------+----------+
    |                           PostgreSQL                                  |
    |  learning_items | error_patterns | rag_misses | dreaming_runs | ...   |
    +--------+-------------------------+-------------------------+----------+
             |                         |                         |
             v                         v                         v
    +------------------+     +------------------+     +------------------+
    |      EVAL         |     |     SKILLS        |     |  CHAIN RUNNER    |
    |                   |     |                   |     |                  |
    | Regression Check  |     | Auto-Improve      |     | Multi-Phase      |
    | Drift Detection   |     | Reflect Loop      |     | Verification     |
    |                   |     | Crystallization   |     | Budget Control   |
    +------------------+     +------------------+     +------------------+
             |                         |                         |
             +------------+------------+------------+------------+
                          |                         |
                          v                         v
                  +---------------+         +---------------+
                  | Vault / Docs  |         | Notifications |
                  | (Obsidian,    |         | (ntfy, email, |
                  |  Markdown)    |         |  webhooks)    |
                  +---------------+         +---------------+
```

## What Does It Do?

| Module | Purpose | Frequency |
|--------|---------|-----------|
| **Dreaming** | Analyzes daily sessions, detects recurring patterns, writes playbooks, proposes skill improvements | Nightly |
| **Learning** | Converts RAG misses and error patterns into learning items, deduplicates, classifies, archives noise | Daily |
| **Brain** | Prioritizes learnings, fills knowledge gaps with stubs, builds cross-links between documents, checks documentation drift | Nightly |
| **Eval** | Detects regressions (same bug fixed twice), measures documentation drift deterministically | Daily |
| **Skills** | Analyzes error patterns to suggest skill improvements, tracks crystallization candidates | Weekly |
| **Chain Runner** | Executes multi-phase tasks autonomously with verification gates, budget limits, and automatic retries | On demand |

## Quick Start

```bash
# 1. Clone
git clone https://github.com/FvdHMBAI/autonomie-os.git
cd autonomie-os

# 2. Configure
cp config.sh config.local.sh
# Edit config.local.sh: set VAULT_DIR, database connection, API keys

# 3. Install (creates DB schema, directories, cron jobs)
./install.sh

# 4. Test a nightly run
./orchestrator.sh --nightly

# 5. Check results
cat ~/vault/autonomie/dreaming/$(date +%Y-%m-%d).md
tail -f /var/log/autonomie/orchestrator.log
```

## Prerequisites

- **PostgreSQL** (any version >= 12)
- **bash** >= 4.0
- **jq**, **curl**, **bc** (standard CLI tools)
- **LLM Provider** (one of):
  - Anthropic Claude API key (recommended for best quality)
  - Local Ollama instance (free, runs on CPU)

## Configuration

Copy `config.sh` to `config.local.sh` and adjust:

```bash
# Required
VAULT_DIR="$HOME/vault"              # Your knowledge base directory
DB_CONTAINER="my-postgres"           # Docker container name (or use DB_HOST)
DB_NAME="autonomie"                  # Database name

# LLM (at least one)
ANTHROPIC_API_KEY="sk-ant-..."       # Claude API key
OLLAMA_URL="http://localhost:11434"  # Local Ollama

# Optional
NTFY_URL="https://ntfy.sh/my-topic" # Push notifications
MONITORED_REPOS="/path/to/app1,/path/to/app2"  # For git analysis
RAG_INDEX_CMD="node /path/to/build-index.js"    # RAG reindexing
RAG_SEARCH_CMD="node /path/to/search.js"        # RAG search
```

## Module Details

### Dreaming (Session Analysis)

Runs after each day to analyze what happened:

1. **Collects** session logs, unapplied learnings, recurring errors, RAG misses, git activity
2. **Triages** all data through an LLM to identify playbook candidates, applicable learnings, patterns, and knowledge gaps
3. **Creates** playbooks for recurring problems, marks learnings as applied, updates error patterns with root causes
4. **Proposes** new skills for patterns that occur 5+ times
5. **Reports** everything in a structured markdown report

### Learning (Continuous Improvement)

A four-stage pipeline that turns raw signals into actionable improvements:

1. **Learning Loop**: Converts RAG misses and high-frequency errors into learning items
2. **Session Learner**: Extracts key findings from session logs
3. **Consolidator**: Clusters by topic, deduplicates, generates category reports
4. **Learning Apply**: LLM classifies items as guard/memory/vault/config/skip, archives noise

### Brain (Knowledge Maintenance)

Active knowledge base maintenance that goes beyond passive logging:

1. **Nightly Brain**: Prioritizes top-5 learnings, analyzes RAG gaps, finds cross-domain patterns, generates creative ideas
2. **RAG Filler**: Creates documentation stubs for frequently missed search queries
3. **Synapse Builder**: Discovers and links thematically related documents using embedding similarity

### Eval (Quality Assurance)

Automated quality checks:

1. **Regression Detection**: When a new bugfix targets the same repo and symptoms as an older fix, flags the older fix as "partial" (likely regression)
2. **Drift Check**: Deterministic measurement of undocumented API routes and database tables across all monitored repos

### Skills (Self-Optimization)

The system optimizes its own skills:

1. **Skill Auto-Improve**: Collects error patterns, runs LLM triage, stages improvement proposals
2. **Reflect Loop**: Scans skill learnings for crystallization candidates (high score + many runs)

### Chain Runner (Autonomous Execution)

Multi-phase task runner for complex work:

- Parses task definitions with phases from markdown files
- Runs each phase in a fresh AI agent session
- Verification gates between phases (TypeScript, build, tests, git status)
- Budget and time limits with automatic stop
- Retry on gate failure
- Full audit trail in vault

## How It All Fits Together

```
  02:00  orchestrator.sh --nightly
           |
           +-> dreaming.sh          Analyze today, write playbooks
           +-> nightly-brain.sh     Prioritize, fill gaps, find patterns
           |     +-> brain-rag-filler.sh
           |     +-> learning-loop.sh
           |     |     +-> session-learner.sh
           |     |     +-> learning-consolidator.sh
           |     +-> learning-apply.sh
           +-> eval-regression.sh   Check for regressions

  08:00  orchestrator.sh --weekly (Sundays)
           |
           +-> dreaming-local.sh    Deep local analysis (7 days)
           +-> brain-synapse.sh     Cross-link documents
           +-> reflect-loop.sh      Find crystallization candidates
           +-> skill-auto-improve.sh Stage skill improvements
```

## License

Business Source License 1.1 (BSL 1.1)

- Free for personal, educational, research, and evaluation use
- Commercial production use requires a Pro license ($49/month)
- Converts to MIT License on 2030-08-01

See [LICENSE](LICENSE) and [PRICING.md](PRICING.md) for details.

## Built by

[Prompt & Build](https://promptandbuild.de) . Battle-tested across 15+ production apps.
