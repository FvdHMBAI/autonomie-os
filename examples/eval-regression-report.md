# Eval Regression Report — Example

This shows how `eval-regression.sh` detects when the same bug is fixed twice, indicating a regression.

## How It Works

Every day at 04:00, eval-regression scans completed bugfix tasks from the last 24 hours. For each new fix, it searches for older fixes in the same repository that targeted similar symptoms (keyword match). If found, the older fix is marked as `outcome=partial`.

## Example Scenario

### Day 1: Original Fix

```
Task #142: Fix login timeout on mobile
  repo: my-app
  category: bug
  status: completed
  completed_at: 2026-07-01
  outcome: null (assumed good)
```

### Day 15: Same Bug Reappears

```
Task #187: Login times out again on mobile after deploy
  repo: my-app
  category: bug
  status: completed
  completed_at: 2026-07-15
```

### Eval Detection

eval-regression runs and finds:

```
Task #187 (new): "Login times out again on mobile after deploy"
  Keywords: login, times, mobile, deploy
  
  Searching for older fixes in 'my-app' with similar keywords...
  
  Match found: Task #142 "Fix login timeout on mobile"
    Keywords overlap: login, mobile, timeout
    Age: 14 days ago
    
  -> Marking Task #142 as outcome=partial
     Reason: "Possible regression: new bugfix 187 for same repo/symptom"
```

### Result

```sql
UPDATE tasks SET 
  outcome = 'partial',
  outcome_reason = 'Possible regression: new bugfix 187 for same repo/symptom',
  outcome_evaluated_at = '2026-07-15 04:00:00'
WHERE id = 142;
```

## What This Tells You

- **Task #142's fix was incomplete** — the root cause was not fully addressed
- **The fix needs investigation** — was it a different bug, or did the original fix regress?
- **Pattern detection kicks in** — if `login-timeout-mobile` appears a third time, the dreaming module proposes a playbook and eventually a skill improvement

## Drift Check

The companion `drift-check.py` module measures documentation completeness:

```json
{
  "apps": {
    "my-app": {
      "doc": "/vault/features/DOMAIN_MODEL.md",
      "routes": ["webhooks", "analytics"],
      "tables": ["audit_log", "notification_preferences"]
    }
  },
  "missing_total": 4,
  "no_document": [
    {"app": "admin-panel", "doc": "/vault/features/ADMIN_MODEL.md"}
  ]
}
```

This means:
- `my-app` has 2 API route groups and 2 tables not mentioned in its domain model
- `admin-panel` has no domain model document at all
- Total: 4 undocumented elements across all apps

The drift report is written to `vault/autonomie/DRIFT_REPORT.md` and tracked over time.
