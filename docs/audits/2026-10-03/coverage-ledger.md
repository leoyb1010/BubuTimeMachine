# Functional coverage ledger (2026-10-03)

Legend: **EXECUTED** = synthetic runtime test this audit; **STATIC** = actual source trace; **INVENTORY** = located only, not tested or complete code review; **PENDING CI** = committed automated test, execution still must be checked for the exact remote SHA; **NOT RUN** = explicit environmental or safety boundary. Test counts are test cases, not the number of product controls validated.

## Journeys and system capabilities

| Journey/capability | Evidence this audit | Result / limitation |
|---|---|---|
| AI input → auth → parse → native-review JSON | EXECUTED: 24 new FastAPI TestClient cases, provider patched locally | 18 failures before fix; all 24 pass after; nullable/scalar containers, malformed domain/tags, nonfinite confidence/numbers, sensitive confirmation, valid multirecord compatibility |
| iOS review → cancel → original input → resubmit → save → timeline | PENDING CI: `testNaturalCaptureCancelThenSaveReturnsToTimeline` | Real SwiftUI/SwiftData; parser alone is deterministic DEBUG in-memory fixture, no live AI |
| iOS review save failure → rollback only its batch → retry | PENDING CI: `WaveNTests.batchFailureIsAtomicAndRetryKeepsUnrelatedDraft` | New autosave-disabled context; unrelated main-context draft retained; checks fresh-context counts before/after retry |
| iOS AI checkup → exact growth-curve measurement | STATIC + PENDING CI: `checkupLinksExactGrowthMeasurement` | Stable link for two same-day checkups; no model/schema change |
| Empty review / repeated same-day vaccine submission | PENDING CI: `emptyBatchAndVaccineRepeatAreSafe` | No empty inserts; preserves existing vaccine dedupe; no claim of durable replay dedupe for all domains |
| Home / tab navigation / identity flip / capture cancel | Existing XCUITests queued on current SHA | iPhone/iPad; inspected navigation source; physical devices not run |
| Timeline search and exact-entry deep link | Existing XCUITests queued on current SHA | Source trace; newer-route interruption race remains static risk |
| School history, reports, correction, reimport, original comparison, interrupted import | Existing XCUITests + unit suites queued on current SHA | Synthetic system PhotosPicker fixtures only; real Photos library never opened |
| Onboarding / account / family-member role | STATIC + backend isolation tests | Entry points inventoried; native signup/login and real accounts NOT RUN; onboarding save errors need separate hardening |
| Quick capture photos / videos / voice / scan / location | STATIC + existing media/unit suites queued | Camera, microphone, location, real Photos/iCloud and interruption hardware NOT RUN; precommit voice/shared rollback risks remain |
| Health / vaccine / measurement forms | STATIC + existing unit suites queued | Natural checkup linkage repaired; vaccine/comment save failure remains identified gap |
| Milestone / first time / storybook / album / family feed | INVENTORY + existing related test sources | Not individually UI-clicked; no runtime completeness claim |
| Diary / growth report / movie / sound-ring / weekly report / QA | EXECUTED: existing server synthetic suites; native UI INVENTORY | Provider calls, production rendering, real source media NOT RUN |
| Time capsule / recovery / export / yearbook | Existing unit sources, Harmony contracts; STATIC capsule/save/export boundary | Real recovery code and private records never loaded; device/share-sheet/export package behavior NOT RUN |
| Sync → record storage → conflict/tombstone replay | EXECUTED: Harmony pure-contract tests + PocketBase real temporary DB | Families, roles, cross-family writes, atomic intake, duplicate replay, migration isolation; no production migration |
| Watch / widgets / notifications / background upload / Spotlight / App Intents | INVENTORY + existing tests queued; Spotlight UI test queued | Permissions, physical Watch delivery, background scheduling, notifications, widgets and App Intents device behavior NOT RUN |
| Harmony ArkUI UI / navigation / forms | Source inventory + Node contract tests | No DevEco/API26 SDK or device; Node/static checks do not prove HAP compile or rendered UI |
| Cross-platform release parity | EXECUTED: original `VersionParity.test.mjs` unchanged | Known baseline failure: iOS 2.19.0 vs Harmony 2.15.0. Platform-internal checks added; release policy unresolved |
| Production backup and restoration | EXECUTED: synthetic local tests, temp SQLite, mock restic; PocketBase integration | Mac mini, launchd, actual backup data, production service never touched |

## Complete located-control ledger

Each row links to the source-level inventory in `controls-inventory.json`, containing control kind, exact file and line. Inventory is a coverage map, not a claim that every button was visually verified. System-provided controls and dynamically repeated items require device runs.

| Source surface / component | Located control expressions | Status |
|---|---:|---|
| `BubuTimeMachine/App/BubuStoreRecoveryView.swift` | 6 | source inventory; not individually clicked |
| `BubuTimeMachine/App/BubuTimeMachineApp.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/App/RootTabView.swift` | 14 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/BubuBigActionButton.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/BubuIOS27Compatibility.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/CeremonyAnimation.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/Components/BubuBufferedField.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/Components/BubuIdentityCard.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/Components/BubuToast.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/Components/MediaViewer.swift` | 6 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/Components/MoodPicker.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/DesignSystem/Components/VoiceComponents.swift` | 4 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/AIStudio/AIStudioHomeView.swift` | 6 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/AIStudio/BubuQAView.swift` | 5 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/AIStudio/FamilyEnsembleView.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/AIStudio/FirstPersonDiaryView.swift` | 3 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/AIStudio/GrowthMoviePlayer.swift` | 3 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/AIStudio/GrowthMovieView.swift` | 8 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/AIStudio/SoundRingView.swift` | 26 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/AIStudio/WeeklyReportView.swift` | 15 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Album/AlbumDetailView.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Album/AlbumHomeView.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Capsule/CapsuleComposeView.swift` | 9 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Capsule/CapsuleHomeView.swift` | 13 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Capsule/CapsuleRecoveryView.swift` | 11 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Capsule/CapsuleUnlockView.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Capture/CaptureHomeView.swift` | 34 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Capture/OnThisDayView.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Capture/QuickCaptureSheet.swift` | 25 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Capture/TodayPhotosSheet.swift` | 17 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Feed/FamilyFeedView.swift` | 3 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Growth/GrowthHomeView.swift` | 6 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Health/GrowthCurveView.swift` | 3 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Health/HealthHomeView.swift` | 12 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Health/HealthRecordSheet.swift` | 22 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Health/SchoolTeacherSheetView.swift` | 4 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Health/SchoolVaccineCheckView.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Health/VaccineQuickLogSheet.swift` | 10 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Health/VaccineView.swift` | 6 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Milestones/BubuConstellationView.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Milestones/MilestoneSheets.swift` | 15 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Milestones/MilestonesHomeView.swift` | 9 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/NaturalCapture/NaturalCaptureBar.swift` | 7 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/NaturalCapture/NaturalCaptureReviewSheet.swift` | 16 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Onboarding/OnboardingView.swift` | 6 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/PhotoFrame/PhotoFrameView.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/School/MemoryJournalComposer.swift` | 19 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/School/MemoryJournalView.swift` | 7 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/School/SchoolJournalHome.swift` | 13 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/School/SchoolReportCard.swift` | 7 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/School/SchoolReportCorrection.swift` | 3 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/School/SchoolReportEditor.swift` | 12 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/AccountView.swift` | 12 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/AdvancedSettingsView.swift` | 6 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/ChildIdentitySettingsView.swift` | 6 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/ChildProfileView.swift` | 11 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/ExportView.swift` | 5 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/MacArchiveWorkspaceView.swift` | 16 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/MembersView.swift` | 15 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/SettingsView.swift` | 11 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/SyncCenterView.swift` | 10 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/ThemeSettingsView.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/VoiceArchiveView.swift` | 7 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/WhatsNewView.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/WidgetWallpaperView.swift` | 7 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Settings/YearbookView.swift` | 3 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Share/ShareCardSheet.swift` | 5 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/SimpleMode/SimpleModeView.swift` | 3 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/SimpleMode/SimpleTimelineView.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Story/BubuStoryReaderView.swift` | 2 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Story/BubuStoryView.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Timeline/CommentComposeSheet.swift` | 4 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Timeline/EntryDetailView.swift` | 24 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Timeline/Reaction.swift` | 1 | source inventory; not individually clicked |
| `BubuTimeMachine/Features/Timeline/TimelineView.swift` | 12 | source inventory; not individually clicked |
| `BubuWatch/Views/WatchMoodView.swift` | 1 | source inventory; not individually clicked |
| `BubuWatch/Views/WatchQuickLogView.swift` | 2 | source inventory; not individually clicked |
| `BubuWatch/Views/WatchRecordView.swift` | 6 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/components/BubuGlassTabBar.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/components/BubuIdentityCard.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/components/BubuMovedHint.ets` | 1 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/components/CeremonyAnimation.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/components/MediaViewer.ets` | 5 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/components/MoodPicker.ets` | 1 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/components/VoiceComponents.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/pages/DataProtectionPage.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/pages/RootPage.ets` | 4 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/AIStudioView.ets` | 5 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/AccountView.ets` | 16 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/AdvancedSettingsView.ets` | 14 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/AlbumDetailView.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/AlbumView.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/BubuConstellationView.ets` | 1 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/BubuQAView.ets` | 8 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/BubuStoryReaderView.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/BubuStoryView.ets` | 1 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/CapsuleComposeView.ets` | 12 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/CapsuleRecoveryView.ets` | 7 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/CapsuleUnlockView.ets` | 3 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/CapsuleView.ets` | 7 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/ChildProfileView.ets` | 14 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/CommentComposeSheet.ets` | 6 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/EntryDetailView.ets` | 20 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/ExportView.ets` | 4 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/FamilyEnsembleView.ets` | 3 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/FamilyFeedView.ets` | 6 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/FirstPersonDiaryView.ets` | 4 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/GrowthCurveView.ets` | 10 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/GrowthHomeView.ets` | 3 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/GrowthMoviePlayer.ets` | 4 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/GrowthMovieView.ets` | 8 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/GrowthReportView.ets` | 1 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/HealthHomeView.ets` | 6 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/HealthRecordSheet.ets` | 28 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/HomeView.ets` | 19 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/MembersView.ets` | 11 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/MilestoneSheets.ets` | 12 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/MilestonesView.ets` | 7 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/NaturalCaptureBar.ets` | 5 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/NaturalCaptureReviewSheet.ets` | 9 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/OnThisDayView.ets` | 1 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/OnboardingView.ets` | 9 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/PhotoFrameView.ets` | 7 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/PhotoInboxView.ets` | 9 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/QuickCaptureSheet.ets` | 12 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/Reaction.ets` | 1 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/SSDIntakeView.ets` | 6 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/SettingsView.ets` | 18 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/ShareCardSheet.ets` | 6 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/SimpleModeView.ets` | 3 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/SimpleTimelineView.ets` | 1 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/SoundRingView.ets` | 15 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/SyncCenterView.ets` | 10 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/ThemeSettingsView.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/TimelineView.ets` | 11 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/VaccineQuickLogSheet.ets` | 10 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/VaccineView.ets` | 2 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/VoiceArchiveView.ets` | 11 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/WeeklyReportView.ets` | 9 | source inventory; not individually clicked |
| `harmony/entry/src/main/ets/view/YearbookView.ets` | 7 | source inventory; not individually clicked |

## Backend routes

- `server/ai/main.py:293`: `@app.post("/school-report/recognize", response_model=school_report.SchoolReportResp)`
- `server/ai/main.py:616`: `@app.get("/health")`
- `server/ai/main.py:638`: `@app.post("/intake/batches")`
- `server/ai/main.py:685`: `@app.get("/intake/batches/{batch_id}")`
- `server/ai/main.py:693`: `@app.get("/intake/candidates")`
- `server/ai/main.py:699`: `@app.post("/intake/confirm")`
- `server/ai/main.py:726`: `@app.post("/intake/candidates/update")`
- `server/ai/main.py:741`: `@app.post("/intake/cancel")`
- `server/ai/main.py:754`: `@app.put("/intake/upload/{batch_id}/{asset_key}")`
- `server/ai/main.py:852`: `@app.post("/intake/commit")`
- `server/ai/main.py:869`: `@app.post("/rewrite-first-person", response_model=RewriteResp,`
- `server/ai/main.py:895`: `@app.post("/classify", response_model=ClassifyResp,`
- `server/ai/main.py:916`: `@app.post("/detect-first-time", response_model=DetectFirstResp,`
- `server/ai/main.py:936`: `@app.post("/movie-narration", response_model=MovieResp,`
- `server/ai/main.py:952`: `@app.post("/ask", response_model=AskResp, dependencies=[Depends(require_api_key)])`
- `server/ai/main.py:982`: `@app.post("/semantic/search", response_model=SemanticSearchResp,`
- `server/ai/main.py:1019`: `@app.get("/weekly-report/latest", response_model=WeeklyReportResp,`
- `server/ai/main.py:1030`: `@app.get("/weekly-report/history", response_model=list[WeeklyReportResp],`
- `server/ai/main.py:1039`: `@app.post("/weekly-report/generate", response_model=WeeklyReportResp,`
- `server/ai/main.py:1051`: `@app.post("/weekly-report/archive", response_model=WeeklyReportResp,`
- `server/ai/main.py:1062`: `@app.get("/weekly-report/events", dependencies=[Depends(require_api_key)])`
- `server/ai/main.py:1098`: `@app.get("/sound-ring/latest", response_model=SoundRingResp,`
- `server/ai/main.py:1108`: `@app.get("/sound-ring/history", response_model=list[SoundRingResp],`
- `server/ai/main.py:1116`: `@app.post("/sound-ring/draft", response_model=SoundRingResp,`
- `server/ai/main.py:1128`: `@app.post("/sound-ring/render", response_model=SoundRingResp,`
- `server/ai/main.py:1137`: `@app.post("/sound-ring/remove", response_model=SoundRingResp,`
- `server/ai/main.py:1150`: `@app.get("/sound-ring/status/{artifact_id}", response_model=SoundRingResp,`
- `server/ai/main.py:1158`: `@app.post("/sound-ring/archive", response_model=SoundRingResp,`
- `server/ai/main.py:1166`: `@app.get("/sound-ring/file/{artifact_id}", dependencies=[Depends(require_api_key)])`
- `server/ai/main.py:1220`: `@app.post("/movie/render", response_model=MovieRenderResp,`
- `server/ai/main.py:1232`: `@app.get("/movie/status/{job_id}", response_model=MovieRenderResp,`
- `server/ai/main.py:1241`: `@app.get("/movie/file/{job_id}", dependencies=[Depends(require_api_key)])`
- `server/ai/main.py:1368`: `@app.post("/parse-natural-capture", response_model=NaturalParseResp,`
- `server/ai/main.py:1455`: `@app.post("/transcribe", dependencies=[Depends(require_api_key)])`

## Accessibility and screenshots

Native visual/accessibility audit is pending current-SHA hosted macOS execution and attachment inspection. No current iOS/Harmony screenshot was fabricated or replaced by a web mockup. CI exports successful and failed synthetic screenshots with three-day retention. VoiceOver/TalkBack, maximum Dynamic Type, focus order, reduced-motion behavior and physical-device targets remain NOT RUN unless a specific runtime check is identified. No full accessibility-compliance claim.
