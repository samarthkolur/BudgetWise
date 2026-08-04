#!/usr/bin/env bash
#
# One command, no dependencies:  ./scripts/install-hooks.sh
#
# Points git at the committed .githooks directory instead of copying files into
# .git/hooks. Copies drift — someone edits a hook, nobody else gets it, and the
# gate silently differs per machine. core.hooksPath makes the hooks part of the
# repository, reviewed like any other code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

git config core.hooksPath .githooks
chmod +x .githooks/*

printf '\033[32m✓\033[0m hooks installed (core.hooksPath = .githooks)\n\n'
printf '  pre-commit  format, analyze, codegen freshness, secrets, config, migrations\n'
printf '  commit-msg  Conventional Commits with a scope allowlist\n'
printf '  pre-push    tests, tracked-config check, history secret scan, database suite\n\n'

if ! command -v gitleaks >/dev/null 2>&1; then
  printf '\033[33m!\033[0m gitleaks is not on PATH. The hooks warn rather than fail without it,\n'
  printf '  but CI does not — install it from https://github.com/gitleaks/gitleaks\n\n'
fi

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  printf '\033[33m!\033[0m docker is unavailable, so pre-push will skip the database suite.\n'
  printf '  CI runs it regardless.\n\n'
fi
