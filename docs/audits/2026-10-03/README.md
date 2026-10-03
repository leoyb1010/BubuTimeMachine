# Two-round functional / product / code audit

## Safety and scope

Source baseline: audit branch `audit/three-round-safety-20261001` at `db032dd2b42bb8b405e527d6931254d6c713fab4` (tree `8ef37944ec89be518c2c6c9aecfd0c5beea7605f`). `main` remains `ae905ab2ec98a62b00e8cba23d4aac0ee7a33ce2`; feature branches verified as `48b8579c8016baccf86a731f639d3561162b3840` and `5a863b3f4843fae8e469e4012af80f95b29625fa`. All remote refs were re-read before work; only the existing audit branch is a publication target.

This is a functional/code audit with a full located-control inventory, synthetic backend and contract execution, and hosted native validation. It is **not** a completed visual audit of every feature. Screenshots cannot be captured locally on the Linux worker; hosted iPhone/iPad checks and screenshots must be read at the exact published SHA. Harmony SDK/device validation is unavailable. No real child/family data, user computer, production server, SSH, deployment, account, purchase, migration, signing key or recovery code was accessed. No schemas, frozen V1 models, production settings or release versions changed.

The inventory locates 1,024 control expressions in 140 source files and 34 backend route declarations. It intentionally distinguishes located source from tested behavior. Concrete current-run flow traces and risk decisions for 14 capability groups are in [flow-traces.md](flow-traces.md). The detailed evidence boundaries are in [coverage-ledger.md](coverage-ledger.md); exact located controls and routes are in [controls-inventory.json](controls-inventory.json).

## Round 1: journey mapping, reproduction and conservative repairs

1. **Malformed AI output breaks the review journey or bypasses confidence safety.** FastAPI TestClient reproductions with local synthetic provider output found null/scalar warning/item/tag containers and non-string domains causing exceptions, tags being split into characters, nonfinite/out-of-range confidence reaching native clients, and damaged fields lacking a review gate. Before patch: 18 of 20 new test cases failed. The sanitizer now guards container types, maps invalid confidence to zero, replaces only nonfinite field numbers with null, preserves valid facts/source text, and requires review for sensitive, low-confidence or repaired fields. All 20 initial cases pass after the repair; four second-round cases cover unrepresentable integers, finite large-value preservation and repeated mixed-validity responses (24 total). No provider or real family endpoint was contacted.
2. **Natural-language review incorrectly reports success after failed persistence.** `saveAll` previously used `try? context.save()`, then played success, cleared source input and dismissed. It now writes the batch in its own autosave-disabled ModelContext; a thrown save rolls back only that batch and leaves the review/original input available for retry. Success callbacks, sync, snapshot refresh and vaccine-reminder refresh occur after commit. A same-view completion guard prevents repeated confirmation during dismissal. This does not claim durable cross-launch idempotency for all natural-record domains.
3. **AI checkup loses its exact growth-measurement relationship.** The router created a GrowthMeasurement but omitted the existing `growthMeasurementId`, forcing later edits into a same-day heuristic and preventing safe exact deletion. New writes set the existing link, without schema change or retrospective mutation. New tests create two same-day measurements and assert distinct correct links. Second-round review also verifies the pre-existing DTO numeric bound; invalid manual numeric text stays visible, blocks saving, and is never silently dropped or passed to an unsafe integer conversion. No new medical range is invented.
4. **Published version/feature-parity claims are stale.** Actual source manifests: iOS 2.19.0/build 2026092605 and Harmony 2.15.0/build 2026091201. Introductory README/matrix text is corrected; both versions are unchanged. Platform-internal manifest/runtime/changelog checks and a factual source-baseline file are added. The original cross-platform `VersionParity.test.mjs` remains unchanged and failing. This audit does not authorize independent release policies or claim Harmony parity.
5. **Capsule plaintext was removed before the record commit.** A narrow production commit boundary now performs plaintext cleanup only after a successful save. A failure/retry temporary-file test checks byte preservation and one post-success cleanup. This does not make all capsule persistence atomic; deletion and failed shared-context retries remain separate risks.
6. **Same-second exports reused the same output directory.** UUID-suffixed roots now prevent mixing independent exports or sharing a ZIP path. A fixed-time regression verifies two real synthetic archives and unchanged first data/manifest; no concurrency-stress claim.
7. **Malformed Harmony deep links could abort lifecycle handling.** The exact production method body was executed against synthetic inputs: four failures before, ten passing cases after a narrow decode catch. Valid URI/ID rules are unchanged.
8. **Successful native UI evidence was discarded.** CI now retains successful as well as failed synthetic screenshots/logs, with existing short retention and test-only permissions. No deployment behavior was introduced.

## Round 2: independent review and failure/retry recheck

- Re-review the changed UI → parser → writer → storage paths and diff; preserve the model/schema/production boundaries above.
- Exercise malformed results repeatedly, valid multirecord compatibility, family-auth isolation, atomic intake replay, same-day checkup links, empty batches, failure then retry, cancellation then resubmission and unrelated-draft preservation.
- New Swift tests use synthetic in-memory stores and injected disk failure. Their source existence is not a pass; current-SHA macOS results are the runtime authority.
- Original cross-platform equality remains a red gate. New local checks must not be described as an overall green CI.

## Local validation evidence

Initial current-baseline checks:
- Duplicate-source and Harmony repository-hygiene gates: passed
- Harmony Node contract tests: 309 passed, 1 failed (original cross-platform version parity)
- AI server baseline after test dependencies: 196 passed, 7 environmental failures (missing rsync), 1 skipped; missing dependency was diagnosed and provisioned in an isolated temporary tool directory
- New API reproductions before repair: 18 failed, 2 passed

After scoped repairs:
- AI server suite, second round: 227 passed, 1 skipped (`sips` exists only on macOS); latest installed framework emits a Starlette/httpx deprecation warning
- New synthetic AI API tests: 24 passed
- PocketBase v0.39.2 real temporary-database tests: 15 passed, including migration, ownership, role, author, cross-family, tombstone and idempotent intake checks
- PocketBase binary matched repository-pinned SHA-256 `054cdf8c52712c4fcab1c515f0e4d9cc0e31d4f4f3bd81d8455b663178e2f146`
- Python compileall and Git whitespace checks: passed
- Complete second-round Harmony suite: 321 passed, 1 failed; the sole failure is the untouched cross-platform parity contract. Both new internal consistency checks passed

The GitHub [audit-branch Actions runs](https://github.com/leoyb1010/BubuTimeMachine/actions/workflows/ci.yml?query=branch%3Aaudit%2Fthree-round-safety-20261001) provide immutable per-SHA iPhone, iPad, Python 3.9 and Harmony results. Hosted results and screenshot inspection are pending at initial publication of this report; the final audit handoff must identify the exact final SHA, terminal jobs, screenshot artifacts and any limitations. Earlier CI results/screenshots are historical context, not evidence for the new patch.

## Explicit remaining risks and release gates

These are source-traced gaps, **not reproduced hardware failures**, and were not folded into a broad data-path refactor:
- CaptureModel has no method-level `!isSaving` reentry guard, starts voice-transcription work before final record commit, rolls back a shared UI context on failure, and may leave imported media files orphaned. The UI disables Save, but interruption/programmatic concurrency and unrelated edits require injectable media/persistence coverage.
- CommentComposeSheet, VaccineQuickLogSheet, onboarding and other inventoried forms still use silent saves followed by success/navigation. Failures can mislead users or leave pending edits; separate per-flow transaction/fault-injection repairs are needed.
- RootTabView clears pending entry routing before an asynchronous delayed push; newer routes or intervening tab changes need explicit interruption tests.
- Capsule plaintext-before-commit cleanup is repaired; metadata-only silent save, failed shared-context inserts/retry duplicates and delete-before-save entry points remain unresolved and are detailed in flow-traces.md.
- Native permissions, real-camera/microphone/Photos/iCloud, actual Apple Watch delivery, notifications/background scheduling, live AI, physical accessibility and Mac Catalyst were not exercised here.
- Harmony API26 build, signed install, upgrade over real data and cross-device runtime parity remain unverified. Node tests include a mix of executed pure logic and source-contract assertions; they are not a native-device acceptance certificate.

## Recovery / review boundary

This patch is isolated to the existing audit branch. Do not merge or deploy until final-SHA native results and the unresolved release-parity contract are reviewed. New records use existing fields only; no migration or mass rewrite is required. A code revert does not require deleting or transforming user data. Do not reset an iPhone database or point tests at the running Mac mini to validate this branch.

## Additional deletion boundary verification

The detail photo/voice and capsule delete entry points now use a dedicated persistent ModelContext. They commit the deletion and remote tombstone before allowing file cleanup, reject stale ownership/remote/parent references and in-memory recovery stores, preserve shared file owners and unrelated UI drafts, and show failure instead of silently claiming success. New disk-backed synthetic SwiftData tests cover injected save failure, retry, ineffective save, stale file identity, unsaved shared ownership, post-commit error, recovery stores and changed parent/remote identity. These tests must pass native CI; their presence alone is not execution evidence. Remaining silent-save/capture-flow risks above are unchanged. The previous native build failed in a throwing assertion in CapsuleV3Tests; its closure now has an explicit throwing signature and reads bytes before asserting.
