#!/usr/bin/env bash
set -euo pipefail
# Usage: db_snapshot_abs.sh [output_path]
ROOT="/Users/home/Workspace/2025_2/real_last/english_ai/server"
ENV_FILE="${ROOT}/.env"
OUT="${1:-${ROOT}/docs/snapshot.sql}"

# load .env
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "ERROR: .env not found at $ENV_FILE" >&2; exit 1
fi

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-ea}"
DB_PASSWORD="${DB_PASSWORD:-ea_pw}"
DB_NAME="${DB_NAME:-english_ai}"

mkdir -p "$(dirname "$OUT")"

# pick dump client
if command -v mysqldump >/dev/null 2>&1; then
  DUMP_BIN="mysqldump"
elif command -v mariadb-dump >/dev/null 2>&1; then
  DUMP_BIN="mariadb-dump"
elif [[ -x "/opt/homebrew/opt/mysql-client/bin/mysqldump" ]]; then
  DUMP_BIN="/opt/homebrew/opt/mysql-client/bin/mysqldump"
else
  echo "ERROR: mysqldump / mariadb-dump not found. Try: brew install mysql-client (or mariadb)" >&2
  exit 2
fi

"$DUMP_BIN" \
  --host="${DB_HOST}" --port="${DB_PORT}" --user="${DB_USER}" --password="${DB_PASSWORD}" \
  --default-character-set=utf8mb4 --single-transaction --skip-lock-tables --no-tablespaces --protocol=TCP \
  "${DB_NAME}" scores_speaking > "$OUT"

echo "Snapshot written to: $OUT"
