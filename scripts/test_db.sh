#!/usr/bin/env bash
#
# Applies every migration to a throwaway Postgres and runs the SQL suites
# against it.
#
# Deliberately does NOT use `supabase start`: this must run in CI and on a
# laptop with nothing but Docker, and it must prove the migrations build a
# working schema from empty every time. supabase/tests/00_auth_shim.sql supplies
# the small part of Supabase the schema depends on.
#
#   ./scripts/test_db.sh            spin up a container, test, tear down
#   DATABASE_URL=... ./scripts/test_db.sh   use an existing empty database
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="budgetwise_test_pg"
PORT="${TEST_PG_PORT:-55433}"
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

if [[ -z "${DATABASE_URL:-}" ]]; then
  command -v docker >/dev/null || { red "docker not found and DATABASE_URL not set"; exit 1; }

  blue "==> starting throwaway postgres on :$PORT"
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$CONTAINER" \
    -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DB=budgetwise_test \
    -p "$PORT:5432" \
    postgres:16-alpine >/dev/null
  OWNS_CONTAINER=1

  DATABASE_URL="postgresql://postgres:postgres@localhost:$PORT/budgetwise_test"

  for _ in $(seq 1 60); do
    if docker exec "$CONTAINER" pg_isready -U postgres -d budgetwise_test >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  docker exec "$CONTAINER" pg_isready -U postgres -d budgetwise_test >/dev/null 2>&1 \
    || { red "postgres never became ready"; exit 1; }
fi

PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 --quiet --no-psqlrc)

blue "==> applying auth shim"
"${PSQL[@]}" -f "$ROOT/supabase/tests/00_auth_shim.sql"

blue "==> applying migrations"
for migration in "$ROOT"/supabase/migrations/*.sql; do
  echo "    $(basename "$migration")"
  "${PSQL[@]}" -f "$migration"
done

blue "==> applying role grants"
"${PSQL[@]}" -f "$ROOT/supabase/tests/01_grants.sql"

# Runs a suite and shows its assertions. psql's exit code is read directly
# rather than through a pipe: piping into grep would report grep's status, and a
# suite that aborted on the first assertion would look like a pass.
run_suite() {
  local name="$1" file="$2" out status
  blue "==> $name"
  out="$(mktemp)"
  set +e
  "${PSQL[@]}" -f "$file" >"$out" 2>&1
  status=$?
  set -e
  # psql prefixes diagnostics with `psql:<file>:<line>: `, so anchoring on
  # NOTICE at the start of the line silently matches nothing.
  sed -nE 's/^.*(NOTICE|ERROR):[[:space:]]+/\1  /p' "$out" || true
  if [[ $status -ne 0 ]]; then
    red "==> $name FAILED"
    tail -20 "$out"
    rm -f "$out"
    exit $status
  fi
  rm -f "$out"
}

run_suite "RLS suite" "$ROOT/supabase/tests/02_rls_test.sql"
run_suite "behaviour suite" "$ROOT/supabase/tests/03_behaviour_test.sql"

green "==> all database assertions passed"
