#!/usr/bin/env bash
set -euo pipefail
# Usage: db_restore_abs.sh [input_sql_path]
ROOT="/Users/home/Workspace/2025_2/real_last/english_ai/server"
ENV_FILE="${ROOT}/.env"
IN="${1:-${ROOT}/docs/snapshot.sql}"

if [[ ! -f "$IN" ]]; then
  echo "ERROR: snapshot not found at $IN" >&2; exit 1
fi

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

# pick sql client
if command -v mysql >/dev/null 2>&1; then
  SQL_BIN="mysql"
elif command -v mariadb >/dev/null 2>&1; then
  SQL_BIN="mariadb"
elif [[ -x "/opt/homebrew/opt/mysql-client/bin/mysql" ]]; then
  SQL_BIN="/opt/homebrew/opt/mysql-client/bin/mysql"
else
  echo "ERROR: mysql client not found. Try: brew install mysql-client (or mariadb)" >&2
  exit 2
fi

"$SQL_BIN" --host="${DB_HOST}" --port="${DB_PORT}" --user="${DB_USER}" --password="${DB_PASSWORD}" \
  --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS \\`$DB_NAME\\` DEFAULT CHARACTER SET utf8mb4;"

"$SQL_BIN" --host="${DB_HOST}" --port="${DB_PORT}" --user="${DB_USER}" --password="${DB_PASSWORD}" \
  --protocol=TCP "${DB_NAME}" < "$IN"

echo "Restore completed from: $IN"
