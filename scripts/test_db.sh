#!/usr/bin/env bash
#
# Runs the server suites against a throwaway MongoDB.
#
# The RLS suite this replaced ran against Postgres and was a second opinion on
# what the database already enforced. These suites carry more weight: MongoDB
# enforces no ownership rules at all, so cross-user separation is exactly as good
# as the assertions in server/test/isolation_test.dart and nothing more.
#
#   ./scripts/test_db.sh                    spin up a container, test, tear down
#   MONGO_TEST_URI=... ./scripts/test_db.sh use an existing MongoDB
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="budgetwise_test_mongo"
PORT="${TEST_MONGO_PORT:-27018}"
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

if [[ -z "${MONGO_TEST_URI:-}" ]]; then
  command -v docker >/dev/null || { red "docker not found and MONGO_TEST_URI not set"; exit 1; }

  blue "==> starting throwaway mongodb on :$PORT"
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  # tmpfs for the data directory: the suite creates and drops databases quickly,
  # and on a disk-backed volume that was enough to make WiredTiger abort with a
  # fatal assertion during index creation.
  docker run -d --name "$CONTAINER" \
    -p "$PORT:27017" \
    --tmpfs /data/db:rw,size=1g \
    mongo:7 --wiredTigerCacheSizeGB 0.25 >/dev/null
  OWNS_CONTAINER=1

  export MONGO_TEST_URI="mongodb://localhost:$PORT"

  for _ in $(seq 1 60); do
    if docker exec "$CONTAINER" mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  docker exec "$CONTAINER" mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1 \
    || { red "mongodb never became ready"; exit 1; }
fi

blue "==> shared domain suite"
(cd "$ROOT/packages/budgetwise_domain" && dart pub get >/dev/null && dart test)

blue "==> server suites (isolation + behaviour)"
(cd "$ROOT/server" && dart pub get >/dev/null && dart test)

green "==> all database assertions passed"
