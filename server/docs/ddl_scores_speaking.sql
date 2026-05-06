-- FILE: english_ai/server/docs/ddl_scores_speaking.sql
CREATE TABLE IF NOT EXISTS scores_speaking (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id VARCHAR(64) NOT NULL,
  session_id VARCHAR(64) NULL,
  transcript MEDIUMTEXT NOT NULL,
  duration_ms INT NOT NULL,
  words INT NOT NULL DEFAULT 0,
  wpm DOUBLE NOT NULL DEFAULT 0,
  filler_count INT NOT NULL DEFAULT 0,
  silence_ratio DOUBLE NOT NULL DEFAULT 0,
  rule_score DOUBLE NOT NULL DEFAULT 0,
  gpt_score DOUBLE NOT NULL DEFAULT 0,
  total_score DOUBLE NOT NULL DEFAULT 0,
  feedback JSON NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_scores_speaking_user (user_id, created_at DESC),
  INDEX idx_scores_speaking_session (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;