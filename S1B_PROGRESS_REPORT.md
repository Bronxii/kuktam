# 
DEPLOY: NO

DIRECT-WRITE RULE CUTOFF: NO

PHASE 4B IMPLEMENTED: NO

COMMIT: NO

PUSH: NO
S1B local implementation status — 2026-10-18

**S1B IS NOT COMPLETE. This is a progress report, not acceptance of the client migration.**

Baseline: `965318d feat(shopping): add safe mutation backend protocol`.
Starting worktree: clean. Backend, rules, Image Import and Android native source
were not edited. No deployment or production access was performed.

## Implemented and locally tested

* Typed request, child, context, status and result domain contracts matching S1A.
* Stable epoch-prefixed 256-bit cryptographic action IDs; immutable persisted
  payload; SHA-256 parity fixture generated with Node/S1A hashing.
* SQLite durable local journal with FULL synchronous commits, unique UID/action
  keys, transactionally enforced queue limit, durable outcomes/notices, UID-bound
  context storage and conservative retention cleanup.
* Bounded dispatcher and Firestore transport foundation. At most ten active parent
  IDs in one query; cache absence cannot cause blind replay; authoritative receipt
  identity/hash checked; no polling and no canonical writes in this transport.
* Old UID callbacks fenced; immutable commands are not rebound to another UID or
  household. Expired missing receipts are unknown historical outcomes, not new
  actions. A duplicate-create rejection checks for an existing server receipt.
* Locally committed actions remain accepted if result observation fails to start.
  Explicit observation recovery reuses existing IDs.

These components **are not yet composed into the running application**.
SQLite reopen tests do not substitute for native process-kill/device evidence.

## Required remaining work

1. Shared session/household/epoch coordinator and one canonical shopping listener.
2. Durable dependent-action scheduling. Never guess the next item revision or
   silently retarget a dependent DELETE when an EDIT merges into a different row.
3. Pending overlay, canonical/receipt ordering reconciliation, durable aggregated
   Hungarian conflict feedback and its acknowledgement.
4. Capture context/revision at dialog/confirmation boundaries; switch every
   ShoppingRepository writer and all calling UI flows to the mutation client.
5. Wire dispatcher recovery at startup/session changes and appropriate network/SDK
   events; handle local outbox cleanup in coordinated account deletion.
6. Real local Flutter-to-Firestore-to-backend E2E, offline/process-death/reconnect,
   multiple clients and original stale ADD / +500 EDIT/DELETE reproductions.
7. Repeat final validation after integration. Green tests of the unused foundation
   do not prove the new application write path.

No external blocker has been established. These are unfinished implementation and
validation requirements; they are not waived or replaced by the foundation tests.

## Requested acceptance report

PHASE S1B FLUTTER CLIENT MIGRATION: FAIL — INCOMPLETE, not a failing-test claim

MUTATION CLIENT: NOT READY for application cutover

OUTBOX IMPLEMENTATION: SQLite/sqflite, UID-keyed immutable request journal

DURABLE OFFLINE: local SQLite commit/reopen tested; complete app/device flow NOT VERIFIED

APP RESTART SAFE: journal reopen PASS; complete application restart NOT VERIFIED

UID ISOLATION: outbox/dispatcher tests PASS; application cutover NOT VERIFIED

MUTATION ID STABLE ACROSS RETRY: YES in implemented foundation

PENDING OVERLAY IMPLEMENTED: NO

CANONICAL DATA FAKED: NO

RESULT OBSERVATION: bounded query dispatcher prototype, not application-wired

PER-MUTATION PERMANENT LISTENER: NO

POLLING: NO

CANONICAL SHOPPING LISTENERS: existing implementation unchanged; shared new coordinator pending

MANUAL ADD MIGRATED: NO

EDIT MIGRATED: NO

DELETE MIGRATED: NO

CHECK/UNCHECK MIGRATED: NO

SHOPPING TEXT IMPORT MIGRATED: NO

RECIPE → SHOPPING MIGRATED: NO

SCALED RECIPE → SHOPPING MIGRATED: NO

OTHER WRITE PATHS: full-list clear also remains to migrate

NORMAL FLUTTER DIRECT canonical shoppingItems WRITES: 8 existing write call sites in ShoppingRepository; target zero NOT achieved

AUTOMATIC LEGACY FALLBACK ADDED: NO; existing repository is not yet switched

ORIGINAL STALE ADD CLIENT E2E: NOT RUN

ORIGINAL +500 LOSS CLIENT E2E: NOT RUN

OFFLINE ADD / EDIT / DELETE / CHECK / IMPORT / RESTART / RECONNECT: new application path NOT VERIFIED

ACCOUNT SWITCH: foundation PASS; complete migrated application NOT VERIFIED

MULTI-CLIENT: new Flutter E2E NOT RUN

BULK 10 / 50 / 200: request serialization PASS; application E2E NOT RUN

FEATURE GATE: existing shoppingRuntime/config.enabled, missing/false OFF; unchanged

PRODUCTION CONFIG CHANGED: NO

## Validation

New foundation tests: 39 PASS. Full Flutter: 1426 PASS, 0 FAIL, 1 intentional SKIP.
Backend unit: 237 PASS, 0 FAIL. Functions TypeScript build: PASS.
Android debug build: PASS; no installation/upload. Native Android source unchanged.
Analyzer: PASS (no issues). Full backend/Firestore emulator: 651 PASS, 0 FAIL.
This includes the S1A mutation/rules, CREATE, invite/email, JOIN reservation,
maintenance, billing and deletion regressions. Diff whitespace check: PASS,
including new untracked source/test files.

These regression results do not substitute for the missing new Flutter E2E.

Read/listener audit: production reads are unchanged because the new dispatcher
is not wired. Its design uses one query over at most ten pending parent IDs,
rebound when that set changes, and detaches when empty. Permission-denied transport
reconciliation adds one bounded server lookup. Each child progress update can
produce a receipt read; BULK therefore is not assumed to cost only one read.
Global session sharing, the authority listener and the canonical-list coordinator
are still pending, so the final application read budget is NOT VERIFIED.

## Files belonging to this work

* SHOPPING_MUTATION_SAFETY.md
* S1B_PROGRESS_REPORT.md
* pubspec.yaml
* pubspec.lock
* macos/Flutter/GeneratedPluginRegistrant.swift (sqflite generated registration)
* lib/shopping/domain/shopping_mutation.dart
* lib/shopping/data/mutations/shopping_outbox.dart
* lib/shopping/data/mutations/shopping_mutation_transport.dart
* lib/shopping/data/mutations/shopping_mutation_dispatcher.dart
* test/shopping/shopping_mutation_contract_test.dart
* test/shopping/shopping_outbox_test.dart
* test/shopping/shopping_mutation_dispatcher_test.dart

S1C FINAL CUTOVER READY: NO

S1 OVERALL COMPLETE: NO

PHASE 4B READY: NO

Reason: application migration/reconciliation/E2E remain unfinished; direct canonical
client writes are still present and rules-permitted. S1C must subsequently close
the rule bypass and validate rollout/rollback before Phase 4B resumes.

PRODUCTION CHANGES: NONE
