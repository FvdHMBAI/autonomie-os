# Changelog

All notable changes to Autonomie-OS are documented here.

## [1.0.0] - 2026-08-02

### Changed
- **License changed from BSL 1.1 to MIT** — fully open source, no restrictions
- Complete README rewrite with architecture diagram, module reference, and configuration guide
- All code and documentation in English

### Added
- Test suite (`tests/test-autonomie.sh`) covering config, modules, orchestrator, SQL schema, chain runner, and sanitization
- GitHub Actions CI with ShellCheck, Python syntax check, SQL validation, and test execution
- CONTRIBUTING.md with code style guide and module structure
- Example documentation:
  - `examples/first-dreaming-session.md` — sample dreaming output
  - `examples/learning-loop-output.md` — learning pipeline walkthrough
  - `examples/eval-regression-report.md` — regression detection example
- CHANGELOG.md

### Removed
- PRICING.md (monetization via hosted services, not license restrictions)
- BSL 1.1 license (replaced with MIT)

## [0.1.0] - 2026-08-01

### Added
- Initial release with 5 module groups:
  - **Dreaming** — session analysis, pattern detection, playbook writing
  - **Learning** — learning loop, session learner, consolidator, apply
  - **Brain** — nightly brain, RAG filler, synapse builder
  - **Eval** — regression detection, drift check
  - **Skills** — auto-improve, reflect loop
- Orchestrator with nightly/weekly/single-module modes
- Chain Runner for autonomous multi-phase task execution
- PostgreSQL schema for learning data
- Installer with interactive setup
- Configuration system with environment variable overrides
- Dual LLM support (Anthropic Claude + Ollama fallback)
- Push notifications via ntfy.sh
