#!/usr/bin/env bash
#
# Runs the shared domain suite and the Node server suite against a throwaway
# PostgreSQL.
#
# The isolation suite carries more weight than a typical integration test:
# Postgres foreign keys stop an orphaned parent id, but nothing in the schema
# stops "this id is real but belongs to someone else" — cross-user separation
# is exactly as good as the assertions in server/test/isolation.test.ts and
# nothing more.
#
#   ./scripts/test_db.sh                       spin up a container, test, tear down
#   DATABASE_TEST_URL=... ./scripts/test_db.sh  use an existing PostgreSQL
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="budgetwise_test_postgres"
PORT="${TEST_POSTGRES_PORT:-5433}"
OWNS_CONTAINER=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[34m%s\033[0m\n' "$*"; }

cleanup() {
  if [[ "$OWNS_CONTAINER" == "1" ]]; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -z "${DATABASE_TEST_URL:-}" ]]; then
  command -v docker >/dev/null || { red "docker not found and DATABASE_TEST_URL not set"; exit 1; }

  blue "==> starting throwaway postgres on :$PORT"
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$CONTAINER" \
    -p "127.0.0.1:$PORT:5432" \
    -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DB=budgetwise_test \
    postgres:16 >/dev/null
  OWNS_CONTAINER=1

  export DATABASE_TEST_URL="postgresql://postgres:postgres@localhost:$PORT/budgetwise_test"

  for _ in $(seq 1 60); do
    if docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1 \
    || { red "postgres never became ready"; exit 1; }
fi

blue "==> shared domain suite"
(cd "$ROOT/packages/budgetwise_domain" && dart test)

blue "==> server dependencies"
(cd "$ROOT/server" && npm install --no-audit --no-fund >/dev/null)

blue "==> applying schema"
(cd "$ROOT/server" && DATABASE_URL="$DATABASE_TEST_URL" npx prisma migrate deploy)

blue "==> server suite (auth + isolation)"
(cd "$ROOT/server" && DATABASE_TEST_URL="$DATABASE_TEST_URL" npm test)

green "==> all database assertions passed"
