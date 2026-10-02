#!/usr/bin/env bash
#
# Starts PostgreSQL and the Node API with no cloud service of any kind.
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

blue "==> starting postgres"
docker compose up -d postgres >/dev/null
for _ in $(seq 1 60); do
  if docker compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1 \
  || { red "postgres never became ready"; exit 1; }
green "    postgres ready on 127.0.0.1:5432"

blue "==> installing server dependencies"
cd server
if [[ ! -d node_modules ]]; then
  npm install
fi

set -a; . ./.env; set +a

blue "==> applying migrations"
npx prisma migrate deploy

blue "==> starting the API"
exec npx ts-node src/index.ts
