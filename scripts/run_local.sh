#!/usr/bin/env bash
#
# Starts MongoDB and the API with no cloud service of any kind.
#
#   ./scripts/run_local.sh
#
# Creates server/.env on first run with a freshly generated signing secret, so
# there is no placeholder to forget to replace.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

green() { printf '\033[32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[34m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }

if [[ ! -f server/.env ]]; then
  blue "==> creating server/.env"
  secret="$(openssl rand -base64 48 2>/dev/null | tr -d '\n' || head -c 48 /dev/urandom | base64 | tr -d '\n')"
  sed "s|^JWT_SECRET=.*|JWT_SECRET=${secret}|" server/.env.example > server/.env
  green "    generated a signing secret"
fi

blue "==> starting mongodb"
docker compose up -d >/dev/null
for _ in $(seq 1 60); do
  if docker compose exec -T mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker compose exec -T mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1 \
  || { red "mongodb never became ready"; exit 1; }
green "    mongodb ready on 127.0.0.1:27017"

blue "==> starting the API"
cd server
set -a; . ./.env; set +a
exec dart run bin/server.dart
