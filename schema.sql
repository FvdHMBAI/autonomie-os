-- =============================================================================
-- AUTONOMIE-OS DATABASE SCHEMA
-- =============================================================================
-- Run this against your PostgreSQL database to create all required tables.
-- The install.sh script runs this automatically.
-- =============================================================================

CREATE TABLE IF NOT EXISTS learning_items (
  id SERIAL PRIMARY KEY,
  source VARCHAR(50) NOT NULL DEFAULT 'manual',
  lesson TEXT NOT NULL,
  applicable_to VARCHAR(200),
  occurrence_count INTEGER DEFAULT 1,
  applied BOOLEAN DEFAULT false,
  applied_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS error_patterns (
  id SERIAL PRIMARY KEY,
  pattern_key VARCHAR(100) NOT NULL UNIQUE,
  category VARCHAR(50),
  description TEXT,
  root_cause TEXT,
  mitigation TEXT,
  related_skill VARCHAR(100),
  occurrence_count INTEGER DEFAULT 1,
  resolved BOOLEAN DEFAULT false,
  resolved_at TIMESTAMP,
  addressed BOOLEAN DEFAULT false,
  severity VARCHAR(20) DEFAULT 'medium',
  first_seen TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rag_misses (
  id SERIAL PRIMARY KEY,
  query TEXT NOT NULL,
  best_score NUMERIC(5,4),
  result_count INTEGER DEFAULT 0,
  session_context VARCHAR(200),
  resolved BOOLEAN DEFAULT false,
  resolved_by VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS dreaming_runs (
  id SERIAL PRIMARY KEY,
  run_date DATE NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',
  sessions_analyzed INTEGER DEFAULT 0,
  learnings_applied INTEGER DEFAULT 0,
  patterns_updated INTEGER DEFAULT 0,
  playbooks_created INTEGER DEFAULT 0,
  skill_proposals_created INTEGER DEFAULT 0,
  rag_gaps_filled INTEGER DEFAULT 0,
  memory_updates INTEGER DEFAULT 0,
  vault_report_path TEXT,
  duration_seconds INTEGER,
  cost_usd NUMERIC(8,4) DEFAULT 0,
  error_message TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS skill_proposals (
  id SERIAL PRIMARY KEY,
  source_sessions TEXT[],
  proposal_type VARCHAR(50) NOT NULL,
  target_skill VARCHAR(200),
  target_section VARCHAR(200),
  proposal_content TEXT,
  evidence TEXT[],
  recurrence_count INTEGER DEFAULT 0,
  confidence INTEGER DEFAULT 0 CHECK (confidence BETWEEN 0 AND 10),
  status VARCHAR(20) DEFAULT 'pending',
  pr_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS skill_decisions (
  id SERIAL PRIMARY KEY,
  skill_name VARCHAR(200),
  decision_type VARCHAR(50),
  judge_decision TEXT,
  was_applied BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS skill_metrics (
  id SERIAL PRIMARY KEY,
  skill_name VARCHAR(200) NOT NULL,
  invoked BOOLEAN DEFAULT true,
  success BOOLEAN DEFAULT true,
  duration_minutes NUMERIC(8,2),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_learning_items_applied ON learning_items(applied);
CREATE INDEX IF NOT EXISTS idx_learning_items_source ON learning_items(source);
CREATE INDEX IF NOT EXISTS idx_error_patterns_resolved ON error_patterns(resolved);
CREATE INDEX IF NOT EXISTS idx_error_patterns_key ON error_patterns(pattern_key);
CREATE INDEX IF NOT EXISTS idx_rag_misses_resolved ON rag_misses(resolved);
CREATE INDEX IF NOT EXISTS idx_dreaming_runs_date ON dreaming_runs(run_date);
CREATE INDEX IF NOT EXISTS idx_skill_proposals_status ON skill_proposals(status);
CREATE INDEX IF NOT EXISTS idx_skill_metrics_name ON skill_metrics(skill_name);
