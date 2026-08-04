# BudgetWise — End-to-End Build Plan

> Companion to `BudgetWise Product Vision and PRD.pdf`. The PRD is the source of truth for **product
> behavior**; this document is the source of truth for **how it gets built**.
>
> **Stack deviation from the PRD (intentional):** the PRD's Technology Stack section names
> Next.js / React Native / NestJS / Prisma / Clerk. This build targets **Flutter + Supabase +
> Google-only sign-in** per the current project decision. Everything else in the PRD — the
> Earn → Save → Invest → Spend philosophy, onboarding, dashboard, ledger, monthly reset,
> investment gating, health score, goals, exports — is implemented as written.
>
> ---
>
> **⚠️ This document is the plan as written on 2026-08-04, before implementation.** Phases 0–6 have
> since been built, and three decisions here were overturned during the build. They are corrected
> inline below and recorded in `CLAUDE.md`, which is the authority on **current state**:
>
> | Planned here | Actually built | Why |
> |---|---|---|
> | Lefthook | Plain shell hooks via `core.hooksPath` | Lefthook not installed; a binary + `node_modules` to check a regex is cost with no return |
> | Riverpod codegen, freezed, json_serializable | Neither — plain providers, hand-written models | `riverpod_lint`/`riverpod_generator` need Dart ≥3.12; this host has 3.9.2 |
> | `with check` clauses for child ownership | Composite foreign keys | Makes the cross-user attack unrepresentable rather than merely policed |

---

## 0. Decision summary

| Area | Decision | Rationale |
|---|---|---|
| Client | Flutter (single codebase: Android, iOS, later Web) | One team, one language, native perf |
| State | ~~Riverpod v2 + `riverpod_generator`~~ → **Riverpod 3, no codegen** | Codegen needs Dart ≥3.12; plain providers work and remove a build step |
| Routing | `go_router` with auth+onboarding redirect guards | Declarative deep-linkable routes |
| Backend | Supabase (Postgres + Auth + Storage + Edge Functions) | Removes the need for a bespoke API tier |
| Auth | **Supabase Auth**, Google as the only enabled provider | One vendor for identity + data; `auth.uid()` is what RLS keys on |
| Data access | Supabase Dart client, direct-to-Postgres, guarded by RLS | RLS *is* the authorization layer |
| Money | `bigint` **minor units** (paise). Never `float`/`double` | Eliminates rounding drift in budget math |
| Local cache | Drift (SQLite) — Phase 7, offline-first | Ship online-first, add offline once schema is stable |
| Hooks | ~~Lefthook~~ → **plain shell + `core.hooksPath`** + `gitleaks` | No extra binary, no Node; the hooks are reviewed like any other code |
| CI | GitHub Actions mirroring the hooks exactly | Hooks are convenience; CI is the gate |

**Non-goals for v1:** bank/UPI integration, OCR receipts, SMS parsing, AI coaching, family
budgeting, Excel *import*. All are PRD "Future Roadmap" items — schema is designed not to block them.

---

## 1. Prerequisites

Verified on this machine: Flutter **3.35.6**, Dart **3.9.2** ✅ · Supabase CLI **not installed** ❌

```bash
# Supabase CLI (Linux)
curl -fsSL https://github.com/supabase/cli/releases/latest/download/supabase_linux_amd64.tar.gz \
  | tar -xz -C /tmp && sudo mv /tmp/supabase /usr/local/bin/

# Lefthook (git hooks runner)
curl -fsSL https://raw.githubusercontent.com/evilmartians/lefthook/master/install.sh | sh

# gitleaks (secret scanning)
go install github.com/gitleaks/gitleaks/v8@latest   # or download the release binary

docker --version    # required for `supabase start` (local Postgres stack)
```

Also needed: a Google Cloud project (OAuth consent screen + client IDs), a Supabase project,
Android Studio / Xcode toolchains.

---

## 2. Repository layout

```
BudgetWise/
├── BUILD.md
├── BudgetWise Product Vision and PRD.pdf
├── lefthook.yml
├── commitlint.config.js
├── .gitleaks.toml
├── .github/workflows/ci.yaml
├── supabase/
│   ├── config.toml
│   ├── migrations/            # timestamped, forward-only SQL
│   ├── seed.sql               # local dev data only
│   └── functions/
│       ├── monthly-rollover/  # optional cron; see §6.5
│       └── push-dispatch/
└── app/                       # Flutter project root
    ├── pubspec.yaml
    ├── analysis_options.yaml
    ├── config/{dev,staging,prod}.json     # --dart-define-from-file; NOT committed
    ├── lib/
    │   ├── main.dart
    │   ├── bootstrap.dart                 # Supabase.initialize, error zone, providers
    │   ├── core/
    │   │   ├── env/            # Env.supabaseUrl, Env.googleServerClientId
    │   │   ├── router/         # go_router + redirect guards
    │   │   ├── theme/          # ColorScheme, typography, budget status colors
    │   │   ├── money/          # Money value type (minor units), formatting, allocation
    │   │   ├── errors/         # AppFailure hierarchy + PostgrestException mapping
    │   │   └── widgets/        # shared atoms
    │   └── features/
    │       ├── auth/           # Google sign-in, session, profile bootstrap
    │       ├── onboarding/     # income → savings → category allocation
    │       ├── dashboard/      # safe-to-spend, savings reminder, category cards
    │       ├── expenses/       # FAB entry sheet, list, edit/delete
    │       ├── ledger/         # monthly ledger view + history
    │       ├── goals/
    │       ├── insights/       # rule-based insights + health score
    │       ├── investing/      # gated module (streak / emergency fund)
    │       ├── export/         # xlsx, csv, pdf
    │       └── settings/
    └── test/ · integration_test/
```

Each feature folder uses the same internal shape: `data/` (Supabase DTOs + repository impl),
`domain/` (immutable models + pure calculation logic), `application/` (Riverpod providers),
`presentation/` (screens + widgets). **All budget math lives in `domain/` and is pure Dart** —
that is what makes it unit-testable without a database.

---

## 3. Data model

### 3.1 Conventions

- Every user-owned table has `user_id uuid not null references auth.users(id) on delete cascade`.
- Money columns are `bigint` in **paise** (₹1 = 100). Percentages are `numeric(5,2)`.
- A month is identified by `period date` normalized to the **first day of month** (`2026-08-01`),
  with a `check (period = date_trunc('month', period)::date)`. Avoids timezone/string-format bugs.
- `created_at timestamptz default now()`, `updated_at` maintained by a shared trigger.

### 3.2 Tables

**`profiles`** — 1:1 with `auth.users`. `id` (PK, FK to auth.users), `display_name`, `avatar_url`,
`currency` (default `INR`), `locale`, `onboarding_completed_at`, `investing_unlocked_at`,
`notification_prefs jsonb`. Created by an `on auth.user created` trigger so the app never has to
race an insert after first sign-in.

**`monthly_budgets`** — one row per user per month. `(user_id, period)` unique.
`income_minor`, `savings_target_minor`, `savings_mode` (`fixed`|`percent`), `savings_percent`,
`savings_confirmed_at` (drives the PRD's savings-transfer reminder → success indicator),
`investment_target_minor` (null until unlocked), `status` (`draft`|`active`|`archived`),
`carried_from_period` (for "reuse last month's allocation").

**`budget_categories`** — allocation per category per month. `budget_id`, `category_key`
(`food`, `transport`, `shopping`, `entertainment`, `bills`, `healthcare`, `subscriptions`,
`education`, `misc`, or `custom:<slug>`), `display_name`, `icon`, `allocated_minor`,
`allocated_percent`, `sort_order`. Unique `(budget_id, category_key)`.

**`expenses`** — `budget_id`, `category_id`, `amount_minor`, `spent_on date`, `note`,
`payment_method` (`cash`|`upi`|`card`|`netbanking`|`other`), `created_at`. Indexed on
`(user_id, spent_on desc)` and `(category_id)`.

**`savings_entries`** — actual saved amounts per month (supports partial saves and the streak).
`budget_id`, `amount_minor`, `saved_on`, `destination` (`bank`|`fd`|`rd`|`cash`|`other`),
`goal_id` (nullable — links savings to a goal per PRD "Goals").

**`goals`** — `title`, `target_minor`, `saved_minor` (maintained by trigger from
`goal_contributions`), `target_date`, `monthly_contribution_minor`, `status`, `icon`.

**`goal_contributions`** — `goal_id`, `budget_id`, `amount_minor`, `contributed_on`.

**`investments`** — only writable once unlocked. `budget_id`, `amount_minor`, `instrument`, `note`.

**`health_scores`** — persisted monthly snapshot: `budget_id`, `score` (0–100), `components jsonb`
(savings_completion, category_adherence, logging_consistency, overspend_avoidance, goal_progress,
investment_completion), `computed_at`. Snapshotted so a past month's score never silently changes.

**`insights`** — generated advisory rows: `budget_id`, `kind`, `severity`, `title`, `body`,
`payload jsonb`, `seen_at`, `valid_until`.

**`notifications_queue`** — `user_id`, `kind`, `scheduled_for`, `payload jsonb`, `sent_at`.

### 3.3 Views / functions

- `v_category_spend` — `budget_categories` LEFT JOIN summed `expenses` → `allocated_minor`,
  `spent_minor`, `remaining_minor`, `pct_used`. The dashboard reads this, not raw expenses.
- `v_budget_summary` — per budget: income, savings target/actual, total allocated, total spent,
  remaining, days remaining in month, `safe_daily_spend_minor`.
- `fn_savings_streak(uid uuid) returns int` — count of consecutive months (ending last completed
  month) where `savings_entries` total ≥ `savings_target_minor`.
- `fn_emergency_fund_ratio(uid uuid) returns numeric` — lifetime savings ÷ 3-month average of
  essential-category spend (`bills`, `food`, `healthcare`, `transport`).
- `fn_investing_unlocked(uid uuid) returns boolean` — `streak >= 6 OR emergency_fund_ratio >= 1.0`,
  matching the PRD. Called on app start; sets `profiles.investing_unlocked_at` once, permanently
  (unlock is not revoked if a streak later breaks — it's an achievement, not a state).

### 3.4 RLS — mandatory, no exceptions

```sql
alter table public.<t> enable row level security;
alter table public.<t> force row level security;

create policy "<t>_select" on public.<t> for select using (auth.uid() = user_id);
create policy "<t>_insert" on public.<t> for insert with check (auth.uid() = user_id);
create policy "<t>_update" on public.<t> for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "<t>_delete" on public.<t> for delete using (auth.uid() = user_id);
```

For child tables (`budget_categories`, `expenses`, `goal_contributions`) carry a denormalized
`user_id` **and** validate parent ownership in the `with check` clause — a denormalized column
alone lets a caller attach a row to someone else's budget.

Anything computed that must not be user-tamperable (health score, unlock flag) is written by
`security definer` functions with `set search_path = public, pg_temp`, and has **no** direct
INSERT/UPDATE policy for the user role.

**Migration discipline:** every schema change is a new timestamped file in `supabase/migrations/`.
Never edit an applied migration. `supabase db diff` to author, `supabase db reset` to verify from
scratch, `supabase db push` to promote.

---

## 4. Authentication — Supabase Auth, Google-only provider

**Supabase Auth is the identity system.** It owns `auth.users`, issues and refreshes the JWT, and
supplies the `auth.uid()` that every RLS policy in §3.4 keys on. There is no Clerk, no Firebase
Auth, no custom token service — the same project serves auth and data, so a session is
authorization for the database with nothing in between.

Google is configured as the single enabled **provider inside** that system. The Google Cloud
setup below exists only so Supabase can validate Google's ID tokens, and the `google_sign_in`
package is only the native account-picker UI — neither holds the session. The app's source of
truth for "who is signed in" is always `supabase.auth.currentSession`.

### 4.1 Provider setup

1. Google Cloud Console → OAuth consent screen (External, add test users during dev).
2. Create three OAuth client IDs: **Web** (this is the `serverClientId` / audience), **Android**
   (needs the SHA-1 of both debug and upload/release keystores), **iOS** (bundle ID).
3. Supabase Dashboard → Authentication → Providers → Google: enable, paste the **Web** client ID +
   secret, and add the Android and iOS client IDs to *Authorized Client IDs* so their ID tokens
   validate.
4. Disable **all** other providers, including email/password and magic link, in Supabase Auth
   settings. Google-only must be enforced server-side, not just by hiding UI.

### 4.2 Client flow (native, not web-redirect)

Use the native Google Sign-In sheet and exchange the resulting **ID token** with Supabase. This
avoids browser redirects, gives the platform-native account picker, and keeps deep-link config out
of the build.

```dart
// features/auth/data/google_auth_service.dart  (google_sign_in ^7.x API)
await GoogleSignIn.instance.initialize(
  clientId: Env.googleIosClientId,        // iOS only
  serverClientId: Env.googleWebClientId,  // audience Supabase validates
);

final account = await GoogleSignIn.instance.authenticate();
final idToken = account.authentication.idToken;
final authz   = await account.authorizationClient.authorizationForScopes(['email', 'profile']);

await supabase.auth.signInWithIdToken(
  provider: OAuthProvider.google,
  idToken: idToken!,
  accessToken: authz?.accessToken,
);
```

> `google_sign_in` v7 replaced `signIn()` with `authenticate()` and moved access tokens to
> `authorizationClient`. **Pin the major version in `pubspec.yaml`** and re-read the package README
> at implementation time before copying this verbatim.

**Fallback if the native flow fights you:** `supabase.auth.signInWithOAuth(OAuthProvider.google)`
uses Supabase's hosted redirect instead — same Supabase Auth, same session, same Google Cloud
client IDs, no `google_sign_in` dependency. The trade is a browser hand-off rather than the native
sheet, plus deep-link config (custom URL scheme on iOS, intent filter on Android) and adding the
callback to Supabase's redirect allowlist. Worth keeping in the back pocket; not the default.

### 4.3 Session & guards

- `Supabase.instance.client.auth.onAuthStateChange` feeds an `authStateProvider`.
- Sessions persist and refresh automatically; no token storage code needed.
- `go_router` `redirect`, evaluated in order:
  1. no session → `/sign-in`
  2. session but `profiles.onboarding_completed_at == null` → `/onboarding`
  3. session but **no `monthly_budgets` row for the current period** → `/onboarding/month`
     (this is the PRD's "if no budget exists for the current month" branch)
  4. otherwise → `/dashboard`
- Sign-out clears the Google account (`GoogleSignIn.instance.signOut()`) **and** the Supabase
  session, then invalidates all Riverpod caches so no user's data can leak into the next session.

### 4.4 Account deletion

Settings → Delete account → Edge Function calls `auth.admin.deleteUser()` with the service-role key
(server-side only). `on delete cascade` removes all rows. Required for both app stores.

---

## 5. Core domain logic (pure Dart, in `core/money` + feature `domain/`)

These are the algorithms worth getting right before any UI exists:

1. **Allocation from percentages** — converting category percentages to paise must sum *exactly*
   to spendable income. Use the **largest-remainder (Hamilton) method**: floor each share, then
   distribute the leftover paise to the largest fractional remainders. Naive rounding leaves
   ±few-paise drift that surfaces as "₹0.03 unallocated" in the UI.
2. **Spendable income** = `income − savings_target − investment_target`. Recomputed live as the
   onboarding savings slider moves (PRD: "the interface instantly demonstrates how savings affect
   available spending money").
3. **Safe daily spend** = `remaining_total ÷ days_remaining_in_month` (inclusive of today, floor to
   the rupee, never negative).
4. **Category status** — `pct_used < 0.75` green, `< 1.0` amber, `>= 1.0` red; over-budget also
   reports the overspend amount and a suggested reallocation from the largest-surplus category.
5. **Savings streak** and **emergency-fund ratio** — mirrored in Dart for display, authoritative in
   SQL for the unlock decision.
6. **Health score** — weighted 0–100: savings completion 30, category adherence 25, logging
   consistency 15, overspend avoidance 15, goal progress 10, investment completion 5 (reweighted
   to the first five while investing is locked). Deterministic and unit-tested against fixtures.
7. **Monthly rollover** — new month with `copy_previous = true` clones category keys and
   percentages, then re-derives amounts from the *new* income. Percentages carry, amounts do not.

Every one of these ships with unit tests **before** its screen is built.

---

## 6. Build phases

Each phase ends in a merged, green-CI, demoable state. Estimates assume one developer.

### Phase 0 — Foundations (2–3 days)

- `flutter create` into `app/`, set package/bundle IDs (`com.<you>.budgetwise`), min SDK 23 / iOS 13.
- `supabase init` + `supabase start`; confirm local stack + Studio.
- Add deps: `supabase_flutter`, `google_sign_in`, `flutter_riverpod`, `riverpod_annotation`,
  `go_router`, `freezed`/`json_serializable`, `intl`, `fl_chart`, `flutter_local_notifications`,
  `excel`, `csv`, `pdf`, `share_plus`, `logger`. Dev: `build_runner`, `riverpod_generator`,
  `custom_lint`, `riverpod_lint`, `very_good_analysis`, `mocktail`, `patrol`.
- `analysis_options.yaml`: `very_good_analysis` + `riverpod_lint`, and treat **warnings as errors**.
- Environment via `--dart-define-from-file=config/dev.json`; `config/*.json` is git-ignored,
  `config/example.json` is committed. (The anon key is publishable, but keep it out of git anyway so
  environments stay swappable — RLS, not key secrecy, is the security boundary.)
- **Install and commit the hook config (§7) now**, before the first feature commit.
- CI workflow: format → analyze → test on every PR.

**Done when:** `flutter run` shows a placeholder connected to local Supabase; a deliberately
badly-formatted commit is blocked by the hook.

### Phase 1 — Auth (2–3 days)

Google Cloud + Supabase provider config, sign-in screen (single button, brand-compliant), native
ID-token exchange, profile auto-create trigger, session guards, sign-out, account deletion,
error states (cancelled, no network, token rejected). Widget test for the sign-in screen, fake
`GoogleAuthService` for the happy and cancelled paths.

**Done when:** first launch → Google sheet → dashboard placeholder; kill/reopen app → still signed
in; sign-out → back to sign-in.

### Phase 2 — Schema + repositories (3–4 days)

All tables, views, functions, RLS policies as migrations. Freezed models + repositories for budget,
category, expense. **RLS test suite**: a second seeded user must get zero rows and a rejected write
on every table — run in CI against a fresh `supabase db reset`, no exceptions.

**Done when:** `supabase db reset` builds the whole schema; cross-user access tests pass.

### Phase 3 — Onboarding (4–5 days)

Three steps per PRD: income → savings goal (fixed *or* percent, with live spendable preview) →
category allocation (sliders, live percent↔₹ conversion, live remaining, largest-remainder
rounding, must total 100%). Writes `monthly_budgets` + `budget_categories` in a single RPC
transaction. Sets `onboarding_completed_at`.

**Done when:** a new user reaches a populated dashboard in under 60 seconds, with allocations
summing exactly to spendable income.

### Phase 4 — Dashboard + expenses (5–6 days)

Summary header (income, savings goal, spent, remaining, days left, **safe daily spend**);
savings-transfer reminder card that flips to a success indicator on confirmation; category cards
with green→amber→red progress and over-budget messaging; FAB → expense entry sheet (amount,
category, note, payment method, date) with optimistic insert and instant recalculation; expense
list with edit/delete; Realtime subscription so a second device stays in sync.

**Done when:** adding an expense updates the category card, remaining balance, and safe daily spend
without a manual refresh.

### Phase 5 — Ledger, monthly reset, exports (4–5 days)

Month ledger (income, savings, allocations, every transaction, remaining balances, summary),
month switcher with historical comparison, new-month detection on launch → "reuse last month's
plan?" flow, and export to **XLSX / CSV / PDF** preserving transactions, category summaries,
monthly stats, savings info and allocations, shared via `share_plus`.

**Done when:** an exported workbook for a completed month reconciles line-for-line with the ledger.

### Phase 6 — Goals, insights, health score, investing unlock (5–6 days)

Goals CRUD with target/saved/remaining/projected-completion/required-monthly-contribution and
savings-to-goal linkage; rule-based insights ("you're at 80% of food with 12 days left",
"transport spending is down 20% vs last month"); monthly health score with component breakdown and
trend; investing module locked behind `fn_investing_unlocked` with a progress indicator ("4 of 6
months") and an unlock celebration.

**Done when:** a seeded 7-month history unlocks investing; a 3-month history does not.

### Phase 7 — Notifications, offline, polish (4–6 days)

Local notifications (salary reminder, savings reminder, daily logging nudge, budget warnings, bill
due dates) with per-type opt-out; Drift cache for read-your-writes offline plus a queued-mutation
sync; empty/error/loading states; dark theme; accessibility pass (contrast, semantics, text scale);
`flutter_native_splash` + `flutter_launcher_icons`; Sentry.

> **Server-side scheduling:** cross-device push (FCM) and any server-initiated reminder needs
> `pg_cron` + an Edge Function reading `notifications_queue`. Local notifications cover v1 — add
> push only if v1 telemetry shows engagement drop-off.

### Phase 8 — Release (3–4 days)

Play Console internal testing + TestFlight, release signing (upload keystore in CI secrets — the
release SHA-1 must be added to the Google Android client or sign-in breaks in production),
privacy policy + data-safety declarations, `--split-debug-info --obfuscate`, staged rollout.

**Rough total: 7–9 weeks** for a solo build at a steady pace.

---

## 7. Pre-commit hooks

Lefthook: one static binary, parallel execution, `{staged_files}` templating, works identically in
zsh and CI.

### `lefthook.yml`

```yaml
pre-commit:
  parallel: true
  commands:
    format:
      root: app/
      glob: "*.dart"
      run: dart format --set-exit-if-changed {staged_files}
      stage_fixed: true

    analyze:
      root: app/
      glob: "*.dart"
      run: flutter analyze --no-pub --fatal-infos --fatal-warnings

    generated-files-current:
      root: app/
      glob: "*.dart"
      run: |
        dart run build_runner build --delete-conflicting-outputs
        git diff --exit-code -- '*.g.dart' '*.freezed.dart' \
          || { echo "Generated files stale — re-stage them."; exit 1; }

    pubspec-lock:
      glob: "app/pubspec.yaml"
      run: git diff --cached --name-only | grep -q 'app/pubspec.lock' \
           || { echo "pubspec.yaml changed but pubspec.lock not staged"; exit 1; }

    secrets:
      run: gitleaks protect --staged --redact --config .gitleaks.toml

    no-env-files:
      glob: "app/config/*.json"
      exclude: "app/config/example.json"
      run: echo "Refusing to commit environment config" && exit 1

    sql-migrations-forward-only:
      glob: "supabase/migrations/*.sql"
      run: |
        git diff --cached --diff-filter=M --name-only -- supabase/migrations \
          | grep . && { echo "Applied migrations are immutable — add a new one"; exit 1; } || true

commit-msg:
  commands:
    conventional:
      run: npx --yes commitlint --edit {1}

pre-push:
  parallel: false
  commands:
    test:
      root: app/
      run: flutter test --coverage --reporter=expanded
    rls-tests:
      run: supabase db reset --local && ./scripts/test_rls.sh
```

### Supporting files

- **`commitlint.config.js`** — `@commitlint/config-conventional`; scopes limited to the feature
  folder names in §2 so history stays greppable per module.
- **`.gitleaks.toml`** — default ruleset plus custom rules for `service_role` JWTs, Google OAuth
  client secrets (`GOCSPX-`), and keystore passwords. The **service-role key must never leave the
  server** — it bypasses RLS entirely, so a leak is a full data breach, not a rotation chore.
- **`scripts/test_rls.sh`** — seeds two users, asserts cross-user reads return 0 rows and writes are
  rejected on every table.

### Rules of engagement

- Install is one command, documented in the README: `lefthook install`.
- Hooks are **fast** (format/analyze/secrets on staged files only ≈ 3–8 s). Tests and RLS checks
  live on `pre-push`, not `pre-commit` — a slow pre-commit hook is a hook people disable.
- `LEFTHOOK=0 git commit` exists as an escape hatch; **CI runs the same checks unconditionally**, so
  skipping locally only defers the failure.

---

## 8. Testing

| Layer | Tool | Coverage target | What it protects |
|---|---|---|---|
| Domain (money, allocation, streak, score, safe-daily-spend) | `flutter test` | **95%+** | The math the whole product rests on |
| Repositories | `mocktail` over the Supabase client | 80% | Query shape, error mapping |
| Widgets | `flutter_test` + `ProviderScope` overrides | key screens | States: loading, empty, error, over-budget |
| RLS / SQL | `pgTAP` or `scripts/test_rls.sh` | every table | Cross-user data leaks |
| E2E | `patrol` | 3 flows | Sign-in → onboarding → dashboard; add expense; month rollover |

Golden tests for the dashboard and category cards in both themes catch unintended visual
regressions. Seed fixtures for 1-month, 3-month and 7-month histories drive the streak, health-score
and unlock tests deterministically.

---

## 9. CI/CD (`.github/workflows/ci.yaml`)

```
PR  → format → analyze → build_runner drift check → unit+widget tests (coverage to Codecov)
    → supabase db reset (service container) → RLS suite → gitleaks full-history scan
    → build APK (debug) as artifact
main→ everything above + patrol E2E on an emulator
tag → release build (signed, obfuscated) → Play internal track + TestFlight
```

Secrets in GitHub Actions: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `ANDROID_KEYSTORE_B64`,
`ANDROID_KEY_PASSWORD`, `APPSTORE_API_KEY`. Migrations promote to staging on `main` and to
production **only on tag**, never automatically from a branch.

---

## 10. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| `google_sign_in` v7 API differs from snippets here | Auth blocked at Phase 1 | Pin the major version; verify against the package README before writing the service |
| Release SHA-1 not registered in Google client | Sign-in works in debug, **fails in production** | Add release SHA-1 during Phase 0; smoke-test a signed build in Phase 8 |
| RLS policy gap on a child table | Cross-user data exposure | Automated cross-user test suite in CI, blocking merge |
| Floating-point money | Silent balance drift | `bigint` minor units enforced by schema + a lint rule banning `double` in money code |
| Month boundaries across timezones | Expense lands in the wrong month | Store `period` as a normalized date; do all month math in the user's local zone, persist UTC |
| Supabase free-tier project pausing after inactivity | Dev friction | Keep local Docker stack as the primary dev target |
| Scope creep from PRD "Future Roadmap" | Ship date slips | Roadmap items are explicit non-goals for v1 (§0) |

---

## 11. Definition of done (v1)

- A new user signs in with Google, completes onboarding, and reaches a working dashboard in under
  60 seconds.
- Adding an expense updates category, remaining balance, and safe daily spend instantly and offline.
- A completed month exports to XLSX/CSV/PDF that reconciles exactly with the in-app ledger.
- A new month prompts for income and offers to reuse the previous allocation.
- Investing stays locked until a 6-month savings streak or a 3-month emergency fund exists.
- A second user cannot read or write a single row belonging to the first — proven by a CI test.
- `lefthook install` + `flutter run` is the entire onboarding for a new contributor.
