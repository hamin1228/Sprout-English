-- FILE: english_ai/server/docs/db_scores_writing.sql
CREATE TABLE IF NOT EXISTS scores_writing (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id VARCHAR(64) NULL,
  input_text LONGTEXT NOT NULL,
  normalized_text LONGTEXT NOT NULL,
  result_edits JSON NOT NULL,
  result_checklist JSON NOT NULL,
  result_warnings JSON NOT NULL,
  score INT NOT NULL DEFAULT 0,
  model_name VARCHAR(64) NOT NULL DEFAULT 'gpt-5',
  guidance_version VARCHAR(64) NOT NULL DEFAULT 'writing_eval_v1_20251011',
  notes LONGTEXT NULL,
  is_deleted TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_user (user_id),
  KEY idx_deleted (is_deleted)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS scores_writing_audit (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  score_id BIGINT NOT NULL,
  action VARCHAR(16) NOT NULL, -- create/update/delete
  snapshot JSON NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_score_id (score_id),
  CONSTRAINT fk_score_id FOREIGN KEY (score_id) REFERENCES scores_writing(id) ON DELETE CASCADE
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;