# Contributing to Autonomie-OS

Thank you for your interest in contributing!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/autonomie-os.git`
3. Create a branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Run tests: `bash tests/test-autonomie.sh -v`
6. Commit: `git commit -m "feat: description of your change"`
7. Push: `git push origin feature/your-feature`
8. Open a Pull Request

## Code Style

- Shell scripts use `set -euo pipefail` (or `set -uo pipefail` where early exit is undesirable)
- Functions are lowercase with underscores: `autonomie_log`, `run_module`
- Constants are UPPERCASE: `MAX_COST_PER_RUN`, `LOG_DIR`
- All log output goes through `autonomie_log` or module-specific `log()` functions
- SQL uses uppercase keywords: `SELECT`, `INSERT INTO`, `WHERE`
- All user-facing text is in English

## Module Structure

Each module follows this pattern:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../config.sh"

LOG="$LOG_DIR/module-name.log"
log() { echo "$(date -Iseconds) $1" >> "$LOG"; }

# Guards (skip file, LLM availability)
# Data collection (DB queries, file scans)
# LLM analysis (if needed)
# Actions (write files, update DB)
# Notification
```

## Areas Where Help Is Needed

- **Additional LLM providers** — OpenAI, Gemini, Mistral adapters in `autonomie_llm()`
- **Alternative databases** — SQLite adapter for simpler setups
- **Visualization** — Web dashboard for learning progress
- **Integration tests** — More test coverage for edge cases
- **Documentation** — Usage guides, architecture deep-dives

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation only
- `test:` — Adding or fixing tests
- `refactor:` — Code change that neither fixes a bug nor adds a feature

## Testing

Run the test suite before submitting:

```bash
bash tests/test-autonomie.sh -v
```

If you add a new module, add corresponding tests in `tests/test-autonomie.sh`.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
