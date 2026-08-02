# Learning Loop Output — Example

This shows how raw signals (RAG misses, error patterns, session logs) flow through the four-stage learning pipeline.

## Stage 1: Learning Loop

The learning loop runs daily and converts raw signals into learning items.

### Input: RAG Misses (last 24h)

```
Query: "how to configure rate limiting"     (searched 4 times, no results)
Query: "backup restore procedure postgres"  (searched 3 times, no results)
Query: "webhook retry configuration"        (searched 2 times, no results)
```

### Input: Error Patterns (>= 5 occurrences)

```
pattern_key: missing-env-deploy    | count: 12 | category: deployment
pattern_key: auth-token-expired    | count: 8  | category: auth
pattern_key: db-connection-timeout | count: 6  | category: database
```

### Output: New Learning Items

```sql
-- Created by learning-loop.sh
INSERT INTO learning_items (source, lesson, occurrence_count)
VALUES
  ('rag_miss', 'Knowledge base has no good coverage for: rate limiting config', 4),
  ('rag_miss', 'Knowledge base has no good coverage for: backup restore procedure', 3),
  ('error', 'Recurring problem: missing-env-deploy - ENV vars missing after deploy', 12),
  ('error', 'Recurring problem: auth-token-expired - Token refresh not triggered', 8);
```

## Stage 2: Session Learner

Extracts findings from session logs written during the day.

### Input: Session Log

```markdown
# Session 2026-07-15: Fix login timeout

## Root Cause
Token refresh was not triggered because the refresh endpoint
returned 401 instead of 200 when the token was expired.

## Fix
Changed auth middleware to distinguish between invalid tokens (401)
and expired tokens (419), retry refresh on 419.

## Lesson
- Auth error codes must distinguish invalid vs expired tokens
```

### Output

```sql
INSERT INTO learning_items (source, lesson)
VALUES ('session', 'Session 2026-07-15-fix-login-timeout.md: Auth error codes must distinguish invalid vs expired tokens');
```

## Stage 3: Consolidator

Clusters, deduplicates, and reports.

### Duplicate Detection

```
Items before: 47
Duplicates removed: 5 (same source + same first 80 chars)
Items after: 42
```

### Topic Clusters

```
deployment: 14 items
authentication: 9 items
database: 7 items
testing: 5 items
rag/vault: 4 items
other: 3 items
```

## Stage 4: Learning Apply (Weekly)

LLM classifies remaining items into concrete action categories.

### Classification Results

```
Item #31 | guard   | Create deployment guard that validates ENV vars before container swap
Item #32 | memory  | Add auth-token-refresh gotcha to agent memory
Item #33 | vault   | Document rate limiting configuration in architecture/
Item #34 | config  | Increase DB connection pool from 10 to 25
Item #35 | skip    | Too vague: "improve error handling" (no specific target)
Item #36 | skip    | Already implemented: webhook retry (added in commit abc123)
Item #37 | skip    | One-time problem: disk full event on 2026-07-10
```

### Report Written

```markdown
# Learning Actions - 2026-07-15

## Summary
- 12 noise items archived (age-based)
- 3 items classified as noise
- 4 concrete actions identified
- 42 items remaining

## Actions
- **[guard]** Item #31: Create deployment guard that validates ENV vars
- **[memory]** Item #32: Add auth-token-refresh gotcha to memory
- **[vault]** Item #33: Document rate limiting in architecture/
- **[config]** Item #34: Increase DB connection pool to 25
```

## The Full Pipeline

```
RAG Misses ──┐
              ├── Learning Loop ──► Session Learner ──► Consolidator ──► Apply
Error Patterns┘     (daily)           (daily)           (daily)        (weekly)
                    
                 Creates items     Extracts from     Deduplicates     Classifies:
                 from signals      session logs      and clusters     guard/memory/
                                                                      vault/config/skip
```
