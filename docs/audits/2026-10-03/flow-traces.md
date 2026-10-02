# Current-run capability traces and risk decisions

This is the second-round source review of actual production functions, supplemented by the named runtime tests. It is deliberately separate from the broad `controls-inventory.json`: locating a control does not prove its behavior. Native runtime results must be read at the exact published SHA in Actions. No physical-device or production-system activity is implied.

## 1. Home, root navigation and simple mode

- Traced: `RootTabView.tabs` → four tabs, compact school navigation, iPad sidebar, `openQuickCapture` → `CaptureHomeView` → `QuickCaptureSheet`; `consumePendingRoute`/`openPendingTimelineEntryIfReady` → UUID-based timeline destination
- Traced: `GrowthHomeView.primaryLinks` and its explicit `AIStudioHomeView` link keep the former studio accessible after the fourth tab became school; `SimpleModeView` separates the current family role from the child's identity and gives camera, voice and recent-photo actions
- Existing native checks on this audit SHA: root labels, identity-card flip, capture dismissal, timeline page, cold exact-entry deep link, iPad landscape
- Good boundary: data-recovery page blocks normal root content when the persistent store fails; DEBUG unit/UI paths use synthetic memory stores and disable configured sync
- Unresolved source risk: `openPendingTimelineEntryIfReady` clears the pending UUID before its delayed task and only rechecks tab selection. A later deep link or intervening tab switch can supersede the request; generation/cancellation tests are needed before changing navigation semantics
- Not exercised: physical accessibility focus order, all Dynamic Type sizes, Catalyst windows, every simple-mode device action

## 2. Capture, camera, Photos, voice and location

- Traced: `QuickCaptureSheet` primary media buttons → source/camera/scanner sheets → `CaptureModel` pending arrays → preview task → `savePickedItems` → Entry/Media/VoiceNote → widget refresh/sync
- Existing safeguards: disabled Save while `isSaving`, explicit discard confirmation for populated drafts, preview task cancellation, all-media-failed error, partial-import warning owned by the still-visible parent, optional location persistence
- Real provider/original-file handling in school import is separately checked below; these are not interchangeable paths
- Unresolved: no model-level reentry guard; precommit transcription launches an asynchronous shared-context save; failed final persistence rolls back the shared UI context, potentially unrelated pending changes; imports can leave unowned local files. Fixing only the button does not solve those ownership problems
- Decision: no broad rewrite of photo/audio persistence or shared-context policy without injectable failed-import/save/interruption tests. Real camera, microphone, location, iCloud and background Photos were not invoked

## 3. Natural-language record → review → persistence

- Traced: `QuickCaptureSheet.naturalCaptureEntry` → `NaturalCapturePanel` → `NaturalCaptureBar.parseText` → configured service / on-device / original-text fallback → `NaturalCaptureReviewSheet` → `NaturalCaptureRouter`
- Executed backend failures: malformed warnings/items/tags, unhashable domains, nonfinite or out-of-range confidence, malformed numeric fields, out-of-Double-range integers, bad item followed by good item, retry after malformed output. Initial 18/20 red; final 24/24 green
- Repaired: UI success/dismiss/source clearing occurs only after a dedicated autosave-disabled batch context successfully saves; failure rolls back only that context and preserves the current draft
- Repaired: exact `growthMeasurementId` for new AI checkups; two same-day facts no longer rely on nearest-date matching
- Repaired: existing DTO finite/<1e9 numeric safety is applied to manual edit parsing; invalid text remains visible. Only the domain's consumed, editable fields can block saving. Unconfirmed excluded records and irrelevant fields cannot lock the eligible subset
- New native checks: failed batch/no partial records/unrelated draft retained/retry, exact same-day links, empty and repeated-vaccine batches, numeric boundaries and repaired input, unconsumed/unchecked-item compatibility, real review Cancel → same source → resubmit → injected save failure → retained review → retry → SwiftData timeline
- Native UI parser and one-shot save-failure fixtures are restricted to DEBUG plus `-uitest-in-memory` plus their explicit fixture flags; provider HTTP behavior is covered separately. Persistent cross-launch idempotency for all domains is not claimed

## 4. Timeline, detail, gallery, comments and sharing

- Traced: `TimelineView` selects capture/creation-time query sorting and opens the wider search window; `TimelineEntryDestination` fetches the requested UUID outside the first page
- Traced: detail text bindings mark `editedAt`/local sync state immediately; append-media flow imports and marks the parent; album grid uses a real-cell pagination sentinel and passes the full media list plus starting UUID to the gallery viewer
- Traced: gallery has missing/decode/download feedback and retry; native photo save reports its completion boolean; sharing passes sanitized images through a system sheet
- Traced: share-card layout availability checks both comparison photos; temporary rendered image is removed on share-sheet dismissal
- Unresolved: timeline soft-delete/Undo and detail edits/appended media/comments still contain `try? context.save()` followed by apparent success. Detail `deleteMedia`/`deleteVoice` remove files before persistence. These require record-specific rollback/file-ownership tests rather than global context rollback
- Runtime boundary: existing deep-link/timeline UI tests run on hosted simulators; album paging at library scale, actual Photos permissions and external share destinations were not exercised

## 5. Health, vaccines, growth and sleep

- Traced: growth root → growth curve / health / vaccine / milestones; `HealthRecordSheet` validates numeric drafts, uses stable growth links first, then legacy date-based association
- Traced: `HealthRecordSheet.save` uses field snapshots to restore failed edits; existing healthy-value and wrong-input tests are included in the native suite
- Repaired natural-checkup link avoids future accidental association of two same-day measurements; original model fields/schema are unchanged
- Unresolved: measurement removal in `HealthRecordSheet` is a second `try?` save; vaccine quick save/delete reports completion after `try?`; phone `HealthHomeView.endSleep` clears the shared start time before save and still ends the activity/shows success on failure
- Decision: flag these specific failure/undo boundaries, without changing historical measurements, vaccine migrations, medical rules or real sleep timers
- Executed related protection: real temporary PocketBase family/author/tombstone tests; Harmony WHO/calendar/health/tombstone suites. These do not establish physical health-screen correctness

## 6. Milestones, firsts, storybook and family feed

- Traced: `MilestoneSheets.save` → update/create + achievement/feed event → throwing save → celebration only after success; delete remains a silent save
- Traced: `GrowthHomeView` uses the shared fact models, latest-measurement resolver and first-time list; no duplicate growth model is created for the summary
- Traced: detail's storybook toggle changes the original Entry and local-sync marker; its toast currently follows a silent save
- Unresolved: failed new milestone save can retain inserted objects in the shared context; subsequent retries need scoped rollback tests. Feed-event success semantics and deletion failure are not fully covered by source inspection
- Existing unit/contract suites are retained; no new content, milestones or family activity was written to an actual account

## 7. Capsule encryption, draft ownership and recovery

- Traced: locked/unreadable capsule permits metadata-only edits; unlocked edit preserves loaded payload fields; v3 seal uses the existing normalized time/recovery code/salt; older formats remain readable
- Found and narrowly repaired: compose previously removed the plaintext voice immediately after encryption, before its database record committed. `CapsuleCommitBoundary` is now called by production compose and performs cleanup only after `persist` succeeds
- New native temporary-file test: injected disk-full failure keeps the same bytes readable; retry with the same draft file cleans once after commit; no-voice save makes no cleanup call
- Explicit limits: this helper is **not** a database-atomicity refactor. Shared-context failed inserts/retry duplicates and metadata-only `try?` success remain unresolved. `CapsuleHomeView.deleteCapsule` still removes ciphertext before a silent model save; it needs a separately tested transactional deletion path
- Recovery keys, crypto versions, existing ciphertext and real capsules are untouched; no actual keychain/recovery data was read

## 8. Settings, onboarding, identities and account state

- Traced: new-family onboarding reuses an existing profile/member when present; join-existing path does not create a second local child and routes to account login
- Traced: account service validates server/username/password, converts username to the existing family-email contract, and persists only after authentication; login reloads service instances and starts sync; logout clears credentials and reloads clients to prevent old-session background work
- Traced: AI URL is checked against trusted packaged/same-origin destinations; memory-test config disables real server configuration; native real-AI availability requires opt-in plus a trusted URL and server credentials
- Traced: member deletion has last-member confirmation/fallback-role protection
- Unresolved: onboarding/member save/delete and parts of identity/profile editing still silently save and advance. Login's asynchronous submission has UI-level busy protection but no method-level single-flight guard; cancellation and credential-store failure deserve synthetic service tests
- No signup, login, logout, password change, permission grant or real credential action was performed

## 9. Sync, tombstones, recovery and role isolation

- Traced: manual `syncNow` resets backoff but does not write in failed-store mode; `syncOnce` awaits completion for background task semantics; force-upload runs behind the same permit and does not mark missing local media uploadable
- Traced: pending deletion consumes remote success/404 and otherwise retains the queue; merge consults pending deletions, current-run generation and existing dirtiness
- Traced: pull collection commits business data and SyncCheckpoint in the same store; errors retain the cursor; checkpoint failure restores only that checkpoint, not unrelated user edits
- Executed twice: 15 real PocketBase v0.39.2 temporary-database tests, including cross-family, membership/role, immutable authors, crypto-version downgrade, tombstone non-revival, startup migration isolation and atomic intake replay
- Executed twice: Harmony pure sync concurrency/snapshot/tombstone tests (some are source-contract checks, explicitly not SDK integration)
- Existing Swift sync/migration/backup regressions run on isolated hosted macOS. No source V1 schema, migration or production server setting changed

## 10. School/report import and original-file preservation

- Traced: PhotosPicker prefers file representations (including video), image-only data fallback, content-based type detection and utility-executor preparation; invalid video/report input rejects without pretending import succeeded
- Traced: originals are retained when optional OCR fails; cancellation inside prepare cleans only its newly owned files; composer checks canceled generations before accepting results
- Traced: draft lease prevents two windows editing one saved draft; corrupt old draft is retained; save checks local files exist; writer uses a dedicated context and stable UUID; recovery removes a draft only when that UUID is already persisted
- Existing native tests cover stopped import, original comparison, auto-save, resumed draft, correction and original reimport, report groups, photo/video system picker. Current-run screenshots must be inspected before visual acceptance
- No installed Photos library, real teacher report or production original was opened

## 11. Open archive, yearbook and incomplete export

- Traced: main-actor snapshots enumerate record references, missing filenames and encrypted capsule salt IDs → background exporter copies media/reports → manifest → zip → incomplete-warning/share branch
- Traced: missing/copy-failed assets are listed, disk capacity is checked, generated manifest hashes actual output and the export is explicitly described as an open-reading package, not full server restore
- Found/repaired: root directory used only a second-resolution timestamp; same-second exports could reuse a directory, skip old destination media and replace a same-named ZIP. A UUID suffix now isolates every export while preserving the cleanup prefix
- New native test creates two real synthetic archives at the same supplied timestamp and verifies distinct roots, first data/manifest unchanged, and both child-name reports independent. This is a deterministic collision regression, **not concurrent stress testing**
- Existing archive hash/tamper/missing-media and recovery-verifier tests are retained. Actual export/share of private family data was not performed

## 12. Watch delivery and phone/widget boundaries

- Traced: nonvoice requests use a fresh autosave-disabled persistent context; undone IDs reject late repeated delivery; same-ID sleep-end checks avoid duplicate records
- Traced: voice reception stages and verifies complete bytes/metadata before generating an acknowledgement; import requires persistent store, stable destination, file integrity, model save and a fresh-context readback before removing the inbox package
- Traced: voice receipts bind source ID, intent and audio digest; late mismatching acknowledgement cannot delete a changed Watch source
- Traced: widget rendering reads lightweight shared JSON only, does not open/migrate SwiftData; missing snapshots show a placeholder; widget image lookup considers shared/legacy thumbnails and downsamples original images; gallery timeline avoids multiplying large image data
- Native WatchInbox, WatchPhotoIntegrity, NotificationReplyInbox, WidgetPhotoPipeline/Wallpaper and migration suite execution is required at the new SHA; physical Watch, WidgetKit scheduling, lock-screen permissions and background delivery remain untested

## 13. AI artifacts, questions and movie continuity

- Traced: diary refuses unconfigured AI rather than saving a mock as family history; questions require cited IDs to be among supplied retrieved records; no source is invented for an uncited answer
- Traced: weekly-report and sound-ring views capture service revision, cancel old operations and discard stale responses; sound-ring polling retains server work after temporary failures and supports offline cached history
- Traced: growth movie stores server job ID, cancels polling when leaving and resumes on return; photo count/caption limits match backend contract
- Unresolved movie continuity: `resumePendingRender` currently removes the saved job on every non-cancellation error, including temporary network failure; `persistMovie` removes an older destination before moving the new file. These need typed-error and atomic-file-replacement tests, not a blind resubmit/deletion change
- Executed server tests: artifact ownership/idempotent creation, weekly-window/query rules, sound render/source integrity, movie URL constraints, auth, semantic retrieval and provider-error handling. Live model/video/media pipelines were not called

## 14. Harmony native lifecycle and deep links

- Traced: EntryAbility awaits database initialization; failure loads DataProtectionPage and returns before regular root/sync/onboarding; optional services have independent error boundaries
- Traced: RootPage's back handling delegates only to the deepest registered handler; growth remains its third tab; notification intents only open prefilled confirmation and do not save immediately
- Found/repaired: malformed percent-encoded external entry URI could throw from `decodeURIComponent` during either cold launch or warm `onNewWant`. Narrow catch returns without changing valid prefix/ID rules or pending target
- Executed actual production method body with only AppStorage stubbed: 10 cases; 4 fail/6 pass before, 10 pass after; includes repeated malformed input, valid encoded ID after failure and missing URI
- Traced: resource deletion in AppDatabase is a transaction covering deletion intent, row and parent dirty state; callers retain files on database errors; capture clears ownership only after successful transaction
- Final local Node suite: 321 pass, 1 unchanged parity failure. This includes pure-runtime and source-contract tests. No Harmony SDK compile, signed install or ArkUI screenshot is claimed

## Remaining acceptance work

- Inspect exact final-SHA iPhone/iPad compile, unit/UI results and exported screenshots; distinguish retries from first-pass success
- Resolve cross-platform version/feature parity policy; original failure is intentionally retained
- Dedicated fault-injection work for the explicitly listed silent-save/delete/file-ownership and movie-resume risks before deploying such changes
- Real device capability matrix (permissions, interruption, offline/lifecycle, accessibility, cross-device sync) using synthetic data on owned test devices, not the production iPhone or Mac mini
