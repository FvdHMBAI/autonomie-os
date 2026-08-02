# First Dreaming Session — Example Output

This is what a typical dreaming run produces after a day of AI agent sessions.

## What Happened

The orchestrator ran `dreaming.sh` at 02:00. It found 6 sessions from the previous day, 4 unapplied learnings, and 3 recurring error patterns.

## Sample Report

```markdown
# Dreaming Report - 2026-07-15

## Summary

| Metric | Value |
|--------|-------|
| Sessions analyzed | 6 |
| Learnings applied | 2 |
| Patterns updated | 1 |
| Playbooks created | 1 |
| Skill proposals | 0 |
| Vault gaps filled | 2 |
| Duration | 47s |
```

## LLM Triage Output

The LLM analyzed all collected data and produced structured findings:

```
PLAYBOOK|502-after-deploy|Traefik returns 502 when new container starts before old one stops|Add health check endpoint, wait for 200 before routing traffic
APPLY|14|Add retry logic to webhook delivery|webhook-handler, add exponential backoff
APPLY|22|Document the user onboarding flow|vault/features/ONBOARDING.md
PATTERN|missing-env-var|Three sessions failed because ENV vars were not set in new containers|Add env-var validation to deployment script startup
VAULTGAP|rate-limiting-config|architecture/RATE_LIMITING.md
VAULTGAP|backup-restore-procedure|playbooks/BACKUP_RESTORE.md
```

## What It Created

### Playbook: `502-after-deploy`

```markdown
# Playbook: 502 after deploy

## Symptom
Traefik returns 502 when new container starts before old one stops

## Diagnosis
Container readiness not checked before traffic routing

## Fix
Add health check endpoint, wait for 200 before routing traffic
```

### Vault Stubs

Two new stub files were created for topics that had no documentation:

- `architecture/RATE_LIMITING.md` — Stub with TODO markers
- `playbooks/BACKUP_RESTORE.md` — Stub with TODO markers

### Learning Items Applied

- Item #14: Retry logic for webhooks — marked as applied
- Item #22: Onboarding documentation — marked as applied

## Notifications

If `NTFY_URL` is configured, a push notification was sent:

```
[Dreaming 2026-07-15] 6 improvements
- 1 playbook created
- 2 learnings applied
- 1 error pattern updated
- 2 vault gaps filled
```

## What Happens Next

- The **nightly brain** runs at 03:00 and prioritizes the remaining learnings
- The **eval regression** check runs at 04:00 and detects if any old bugfixes regressed
- On Sunday, the **weekly run** will cross-link the new vault stubs with existing documents
