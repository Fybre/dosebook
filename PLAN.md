# Bench for iOS: build plan

A native SwiftUI port of [ArunNGun/Bench](https://github.com/ArunNGun/Bench) (MIT), a tracker for
peptide, growth hormone and anabolic protocols. It syncs through iCloud, and a macOS app that
reads the same data is planned for later.

Status as of 2026-10-22: Phases 1–8 done; Phase 9 (hardening) done except what needs real devices. See section 6.

---

## 1. Decisions already made by the user

| Question | Answer |
|---|---|
| Approach | **Native SwiftUI**, not a Capacitor wrapper of the web app |
| Scope | **Full feature parity** with the web/Android app |
| Theme | **Standard iOS look** (grouped lists, SF Symbols) with a **teal/mint accent**, in light and dark. The user dislikes the Android app's red theme. |
| Sync | **iCloud** (CloudKit private database), so a future macOS app can read the same data |

Defaults chosen by me, which the user can override:
- Minimum OS: iOS 18 and macOS 15 (for the later Mac target).
- Bundle id placeholder: `com.craigmewett.bench`. The iCloud container is `iCloud.com.craigmewett.bench`.
  The user must set their own `DEVELOPMENT_TEAM` for signing and CloudKit.
- English first. Translations (de/sl/pl, about 5.9k lines in `src/lib/i18n/translations.ts`) come later:
  a script will generate a `Localizable.xcstrings` from that file.

## 2. Environment notes (this Mac)

- Xcode 27.0 is at `/Applications/Xcode.app`, but `xcode-select` points at the Command Line Tools.
  Prefix commands with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or ask the
  user to run `sudo xcode-select -s /Applications/Xcode.app`.
- Swift 6.4. Simulators include iPhone 17 / 17 Pro with iOS 26.x–27.0 runtimes.
- **XcodeGen 2.46 was installed with brew** and is used to generate the `.xcodeproj` from `project.yml`.
- Node v25.8 is available, used for the library export script.
- Reference repo clone: it was in the session scratchpad, which is temporary. Re-clone with
  `git clone --depth 1 https://github.com/ArunNGun/Bench <scratch>/ref/Bench`. Keep it **outside**
  this project. It is untrusted downloaded code, so don't run its npm scripts. Read it only.
- This directory is not a git repo yet. Run `git init` when scaffolding.

## 3. What the source is (sized up)

About 60k lines of TypeScript including tests, and about 44k without them.
Next.js 15 + React 19 + Zustand persisted to IndexedDB + Capacitor (Android).
The original's own docs are in `document/01-product.md` … `07-status.md` and `CLAUDE.md`. Read
`document/06-traps.md` before porting any logic.

Principles from the original that the port must keep:
- **Components never compute doses.** All arithmetic lives in pure, tested modules (`src/lib/calc`).
- U-100 vs U-40 is never assumed. The scale is always an explicit choice, and the reading on the
  other scale is shown alongside.
- Blends are decomposed per component (`blend.ts`), with weekly comparison.
- Every dose figure carries its evidence level. Where a half-life is unknown, `halfLifeHours = null`
  and no curve is drawn. `halfLifeEstimate` figures are drawn but never asserted.
- **Data must survive every update**: `migrateAppData` is shared by persistence and import, and
  restored rows must be *visible* (every screen filters by `profileId`, and orphaned rows are adopted).
- "Rescue": a write that empties a whole collection keeps the previous copy aside (`calc/rescue.ts`).
- Health data is **read only**. That was Health Connect; on iOS it becomes HealthKit, read only.
- Reminders are **local only**, off until switched on, and discreet by default (no compound name).
- No new network calls. iCloud replaces the self-hosted sync server.

### Source map (non-test line counts)

- **Types:** `src/lib/types.ts` (1242). `DATA_VERSION = 9`. AppData collections: `profiles, measurements, labs,
  activeProfileId, protocols, logs, vials, settings, customPeptides, checkIns, halfLifeOverrides (map),
  compoundNotes, orders, diluents`.
- **Calc** (`src/lib/calc`): schedule 854, inventory 704, reconstitution 427, pk 399, stack 374, cost 272,
  diluent 269, healthsync 268, checkins 239, custom 228, progress 228, spray 228, labs 224, pct 222,
  infer 217, sites 208, ics 207, blend 186, rescue 184, outcomes 175, palette 170, reminders 144,
  project 142, document 120, backupnag 118, tablet 111, barrel 105, profiles 85, feeling 81,
  dosecsv 84, units 79, phase 66, firstBackup 48, numberField, converter.
- **Data:** `src/lib/data/peptides/{metabolic,repair,growth,anabolic,ancillary}.ts` (about 2.7k, 49 compounds),
  `src/lib/data/labs.ts` (16 markers). These files import types only, so they are easy to export to JSON.
- **Other lib:** `store.ts` 1016 (all mutations), `migrate.ts` 286, `format.ts` 301, `changelog.ts`,
  `recover.ts`, `import/*` (delimited, xlsx, pdf, labreport, profiles, pipeline, plan, values),
  `notify/*`, `health/*`, `backup/*`, `sync/*` (**not ported**; replaced by iCloud).
- **Screens** (`src/app`): Today `page.tsx` 1387, `stock` 1949, `plan` 1073, `settings` 785, `log` 482,
  `labs` 445, `calculator` 404, `report` 367, `library` + `[slug]/PeptideDetail` 604, `about` 238.
  `landing/*` is **not ported** (marketing).
- **Components of note:** LogDoseSheet 1063, ui.tsx 568, ImportPanel 541, WeightCard 432, Syringe 405,
  PkChart 380, SyringePicker 351, CustomCompoundForm 319, PhaseEditor 316, SiteMap 274,
  ProfileSwitcher 274, CheckInCard 269, RemindersPanel 264, PctPanel 205, ProjectionPreview 176,
  CheckInSheet 168, PkReadout 149, CompoundNotes 130, CheckInEditor 130, BlendBreakdown 127,
  LabsCard 126, YourHalfLife 116, DoseMarks 119, StackWarnings 105, TimesOfDay 133, HistoryWithoutPlan 160,
  RescueNotice 137, BackupNag 121.
- **Not ported:** SyncPanel/SyncRunner/SyncNotice/UnlockGate/AdminPanel (self-hosted sync),
  InstallPrompt/UpdatePrompt/UpdateButton (PWA), LangDropdown (until i18n), landing.

## 4. Architecture

```
bench2/
  project.yml                 XcodeGen spec: iOS app target (+ macOS later), tests
  PLAN.md
  README.md
  tools/
    export-library.mjs        TS library -> JSON (copies data files to a temp dir, rewrites
                              extensionless imports to .ts, runs with node type stripping)
  BenchCore/                  Swift package, pure logic, no SwiftUI, no I/O
    Package.swift
    Sources/BenchCore/
      Model/                  Codable structs mirroring types.ts (JSON-compatible with Bench backups)
      Calc/                   1:1 ports of src/lib/calc/*.ts
      Data/                   Library loader; Resources/peptides.json, labs.json
      Import/                 CSV/TSV/JSON/XLSX/PDF readers
      Migrate.swift, Format.swift, Rescue.swift
    Tests/BenchCoreTests/     ports of the key test files
  Bench/                      SwiftUI app
    App/                      BenchApp, root TabView, theme (teal accent)
    Persistence/              SwiftData + CloudKit store, AppStore
    Features/                 Today, Plan, Log, Stock, Calculator, Library, Labs, CheckIns,
                              Settings, Report, About, Import
    Components/               Syringe, SyringePicker, PkChart, SiteMap, etc.
    Platform/                 HealthKit (read only), local notifications, ICS export, share/export
```

### Domain model (BenchCore)
- Port every type in `types.ts` as an `Equatable, Codable` struct or enum. Use the **same JSON keys**,
  so a Bench backup (`.json` export) imports directly and exports stay compatible with the web/Android app.
- Rename `Protocol` to `DoseProtocol`, because `Protocol` collides with a Swift keyword.
- Timestamps stay as epoch **milliseconds, `Double`**, matching JSON.
- Enums keep their string raw values (`"interval-days"`, `"abdomen-ul"`, `"U100"`…). Decoding must be
  **lenient**: an unknown enum value or extra field must not fail an import. Preserve unknown
  top-level fields where practical (migrate.ts deliberately carries them through).
- JS semantics to replicate: `Math.round` is round-half-up (`floor(x+0.5)`), unlike Swift's `.rounded()`
  for negatives. Replicate `toFixed` + `Number()` trimming (`trim()` in format.ts). All schedule
  maths is **local time**, so use `Calendar.current` and test across DST (the original runs tests with
  `TZ=America/New_York`).

### Persistence and iCloud sync
- **SwiftData** with `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.craigmewett.bench"))`.
- **Envelope-record design** (CloudKit-friendly: every attribute optional or defaulted, no unique
  constraints, no relationships):
  ```swift
  @Model final class Record {
    var kind: String = ""        // "protocol","log","vial","measurement","lab","checkIn",
                                 // "customPeptide","compoundNote","order","diluent","profile",
                                 // "settings","halfLifeOverride"
    var recordId: String = ""    // domain id (peptideId for overrides, "settings" for the singleton)
    var profileId: String?
    var payload: Data = Data()   // JSON of the domain struct
    var updatedAt: Date = .distantPast
  }
  ```
  The domain schema can then evolve without CloudKit schema migrations, and conflicts resolve as
  last-writer-wins per row.
- **AppStore** (`@Observable`, main actor) holds an in-memory `AppData`, mirroring the Zustand store.
  Every action from `store.ts` is ported as a method that calls `mutate { data in … }`. `mutate`
  diffs old against new per collection by id (with Equatable), upserts the changed rows, deletes the
  removed ones, and stamps `settings.dataChangedAt`. Before saving, it runs the rescue check
  (`rescue.ts`) and keeps the prior collection if one would be emptied.
- On load, **dedupe** by `(kind, recordId)`, keeping the newest `updatedAt` and deleting the rest.
  This covers two devices creating the same singleton or default profile `"me"`. Then run
  `migrateAppData` and rebuild `AppData`.
- Reload on `NSPersistentStoreRemoteChange` and when `scenePhase` becomes active.
- `activeProfileId` is **per device** (UserDefaults). It is still written into exports.
- Fallback: if CloudKit is unavailable (no account or entitlement, or an unsigned simulator), use a
  local-only store and show the sync state in Settings.
- The future macOS app reuses BenchCore + Persistence + most views as a multiplatform target.

### Theme
System colours and grouped `List`/`Form` styles. A teal accent (for example `Color.teal`, or a custom
asset with light and dark variants). Profile tones (`mint, grape, tangerine, sky, rose, leaf`) map to
SwiftUI colours. Charts use **Swift Charts** (PK curves, weight, labs, check-ins). The syringe and
body site map are hand-drawn with SwiftUI `Canvas`/`Shape`, porting `barrel.ts` tick logic exactly.

### Platform replacements
| Original | iOS |
|---|---|
| IndexedDB + self-hosted encrypted sync | SwiftData + CloudKit private DB |
| Android rotating backups to Documents/Bench | Manual JSON export via share sheet / `fileExporter`. Optional auto-backup to the app's iCloud Drive folder, keeping the last N |
| Health Connect (read only) | HealthKit read only: body mass, sleep, resting HR → `Measurement(source: "health-connect"`-equivalent, `externalId` = HK UUID) |
| Android AlarmManager reminders | `UNUserNotificationCenter` local notifications (64 pending max, so arm the nearest ones; discreet by default) |
| ICS calendar export | Keep (`ics.ts`), shared as a `.ics` file |
| Browser print report | SwiftUI view → `ImageRenderer`/PDF + share |
| PDF lab report import (pdf.js) | PDFKit text extraction → `labreport.ts` port |
| XLSX import | Minimal zip + sheet XML reader (port `xlsx.ts`), or a vetted small SPM package |

## 5. Work order (phases)

Each phase ends with `swift test` (BenchCore) and an app build for the simulator:
`xcodebuild -scheme Bench -destination 'platform=iOS Simulator,name=iPhone 17' build`.

1. **Scaffold.** Run `git init`, create `project.yml`, the BenchCore package, the app shell with a TabView
   (Today, Plan, Log, Stock, More), the teal theme, and entitlements (iCloud/CloudKit, HealthKit,
   background remote notifications for CloudKit).
2. **Library export.** Write `tools/export-library.mjs` to produce `peptides.json` (49 compounds) and `labs.json`
   (16 markers) as BenchCore resources, plus a test that every compound decodes and the ids are unique.
3. **Model + migrate + format.** Port `types.ts`, `migrate.ts` (incl. the v2 vial drawnMl→drawnMcg,
   orphan adoption, check-in day dedupe, note dedupe, sane overrides/orders/bottles), and `format.ts`.
   Add a round-trip test with a real Bench export.
4. **Calc core**, porting tests alongside: reconstitution, barrel, units, spray, tablet, diluent,
   schedule (DST tests), phase, sites, inventory, cost, blend, pk, project, stack, pct, progress,
   outcomes, labs, checkins, feeling, profiles, custom, infer, reminders, ics, rescue, backupnag,
   firstBackup, document, dosecsv, palette, numberField, converter.
5. **Persistence.** Build the SwiftData envelope store, AppStore with all `store.ts` actions, the diff
   writer, rescue, dedupe, remote-change reload, and the local fallback.
6. **Screens, in priority order:** Today (due doses, log button, check-in card, weight card, stack
   warnings, rescue/backup notices) → LogDoseSheet + SyringePicker + Syringe → Plan (protocols,
   schedule kinds, times of day, titration, PhaseEditor, sites, projection preview) → Log
   (history, edit, CSV export) → Stock (vials lifecycle, orders/shipping, diluent bottles,
   spray bottles, packs, grouping, cost) → Calculator → Library + PeptideDetail (evidence tags,
   PK chart, PkReadout, BlendBreakdown, YourHalfLife, CompoundNotes, custom compounds) → Labs →
   Check-ins → PCT/Recovery panel → Report → Settings (profiles, units, currency, reminders,
   backup/export/import, iCloud status, theme) → About/changelog.
7. **Import.** JSON backup (via migrate), CSV/TSV/XLSX through the pipeline (Shotsy profile by name,
   others by header), and PDF lab reports via PDFKit.
8. **Platform.** HealthKit read, local reminders, ICS export, report PDF, app icon (generate from
   `assets/brand-icon.svg` recoloured teal).
9. **Hardening.** Test CloudKit on two devices, DST, large-dataset performance, and the accessibility
   pass (Dynamic Type, VoiceOver on the syringe).
10. **Later.** macOS target, localisation from `translations.ts`, widgets.

## 6. Where the last session stopped

**Done (all committed, `./tools/test.sh` green in four time zones):**
- `git init`, `.gitignore`, `BenchCore` Swift package (`swift-tools-version 6.0`, iOS 18 / macOS 15).
- `tools/export-library.mjs` → `BenchCore/Sources/BenchCore/Resources/{peptides,labs}.json`
  (50 compounds, not 49; 16 markers). `Library` loads them.
- Model (`Model/`): all of `types.ts`. Design decisions taken while porting:
  - String unions are `StringEnum` **structs** (raw string + static constants), so an unknown value
    round-trips instead of failing an import. `switch` still matches the constants.
  - Every row type is `Extensible`/`Row`: unknown JSON keys are kept in `extra` and written back
    out (via the `Lenient<T>` coding wrapper), per row, not just at top level. This matters more here
    than in the web app, because each row also travels through CloudKit on its own.
  - `AppData` decodes leniently: a row that cannot be read as its type is kept in `unreadable[key]`
    and re-exported, never dropped. Top-level unknown keys go to `AppData.extra`.
  - `Measurement` is `BodyMeasurement` in Swift (Foundation clash); JSON is unchanged.
  - `JSMath.swift`: `jsRound` (Math.round), `jsToFixed` (exact toFixed incl. ties away from zero),
    `jsNumberString`, `stableSorted` (JS sort is stable), `OrderedMap` (JS Map insertion order).
  - `LocalTime.calendar` (`@TaskLocal`, default `.autoupdatingCurrent`) is the only calendar the
    schedule maths uses.
- `Migrate.swift` (all of migrate.ts, idempotent; v1 `drawnMl` arrives via `extra`).
- Calc ported **with their tests**: schedule, inventory, reconstitution, cost, units, barrel, spray,
  tablet, phase, diluent, converter, numberField, sites, blend, pk, project, stack, pct, progress,
  outcomes, labs, checkins, feeling, profiles. (`Tone` enum stands in for ui.tsx's Tone.)

**Build/test notes:**
- Use the Xcode toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`), or
  `import Testing` fails.
- Build outside `~/Documents` (`--scratch-path $TMPDIR/bench2-build`): iCloud-synced Documents
  adds extended attributes and codesign of the test bundle fails. `tools/test.sh` does both.

- Remaining calc ported with tests (custom, infer, reminders, ics, rescue, backupnag, document,
  dosecsv, palette, healthsync), `Format.swift`, i18n (`translations.json` exported from
  translations.ts, iOS-only strings in `ios-strings.json`, all four languages).
  Not ported on purpose: firstBackup and sync (hosted sync), recover.ts (web chunk recovery),
  changelog.ts (iOS gets its own).
- `Store/Actions.swift`: every store.ts action as an `AppData` mutation.
- `BenchStore`: envelope records in SwiftData (CloudKit private DB when signed in, local
  otherwise), per-row diff writes, dedupe on load, row order kept across reloads, rescue copy,
  `AppStore.mutate {}`.
- App (XcodeGen `project.yml`, `Bench.xcodeproj` is generated and ignored): every screen of the
  original. Now, Plan, Log a dose (drawn syringe), Log (diary), Stock (vials, groups, orders, packs,
  sprays, water shelf), Calculator, Library + peptide detail, Bloodwork, Report (PDF via
  UIMarkupTextPrintFormatter), Settings, About (iOS changelog, MIT notice for the original).
- Import (`BenchCore/Import`): CSV/TSV, JSON (ordered keys), xlsx (own zip reader + Compression
  inflate), PDF text layer, lab reports, Shotsy and generic profiles, import plan. All original
  tests ported. The app adds a PDFKit fallback for PDFs the built-in reader cannot follow.
- Platform: local notifications re-armed on every change (`Platform/ReminderScheduler`), ICS via the
  share sheet, HealthKit read-only (weight sync, weight prefill, sleep and resting HR onto vitals;
  stored with source `health-connect` for file compatibility, ids prefixed `hk:`), rotating backups
  in Documents/Bench (visible in Files), app icon (`tools/make-icon.swift`).
- Hardening done: performance over three years of history (chart prefilters doses, Stock outlook
  cached; tests in BenchStoreTests), Dynamic Type at accessibility sizes, VoiceOver labels.
- Debug launch args: `-demo`, `-demoLarge`, `-tab now|plan|log|stock|more`, `-anchor <id>`,
  `-log [peptideId]`, `-more calculator|library|labs|report|settings|about|importer [peptideId]`,
  `-importFile <path>`, `-editCompound <id>`. `tools/shot.sh <tab> out.png [args]` builds, launches and screenshots.

**Needs the user / real devices:** set `DEVELOPMENT_TEAM` in project.yml; then test CloudKit sync
between two devices on one Apple ID, HealthKit permission and reads on a phone, notification
delivery, and Files visibility of Documents/Bench.

**Later:** macOS target, widgets.
