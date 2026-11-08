# Architecture

CleanMac is a single Swift Package Manager target (`executableTarget`) with no external dependencies. The UI is written in SwiftUI; AppKit is used only where SwiftUI has no equivalent: Finder interaction, the Trash, window management.

## Overview

```
┌───────────────────────────── SwiftUI views ─────────────────────────────────┐
│ AssistantView  SmartCleanView  ExplorerView  DuplicatesView  JunkView  …    │
└───────────────▲──────────────────────────────────────────┬──────────────────┘
                │ @Published state                         │ user action
┌───────────────┴──────────────────────────────────────────▼──────────────────┐
│ AppState  (@MainActor ObservableObject, single source of truth)             │
│  scanning · duplicates · junk · smart plan · rules · safe removal           │
└──────┬─────────────┬──────────────┬──────────────┬──────────────┬───────────┘
       │ Task.detached (background, cancellable)                  │
┌──────▼─────┐ ┌─────▼────────┐ ┌───▼──────────┐ ┌─▼────────────┐ ┌▼──────────┐
│ DiskScanner│ │DuplicateFinder│ │ JunkScanner │ │ SmartPlanner │ │ Shell     │
│ (parallel) │ │ SimilarPhotos │ │ AppInventory│ │ RuleEngine   │ │ brew/tmutil│
└────────────┘ └───────────────┘ └─────────────┘ └──────────────┘ │ docker…   │
                                                                   └───────────┘
```

- **Views** read state and call methods on `AppState`. They never touch the file system directly.
- **`AppState`** lives on the main actor. It sends heavy work to the background with `Task.detached` and writes the results to `@Published` properties.
- **Engines** (`DiskScanner`, `DuplicateFinder`, `JunkScanner` …) are pure, stateless types. They take input and return values, so they can be tested directly.

## Files

| File | Responsibility |
|---|---|
| `CleanMacApp.swift` | Entry point (applies the language, then starts the app), window and menu bar scenes, sidebar, menu commands |
| `AppLanguage.swift` | Interface language preference, applied at launch; relaunch |
| `AppState.swift` | Central state and every workflow; the single removal path `remove(_:permanently:)` and `safetyProblem` |
| `Models.swift` | `L()`, `Paths`, `FileNode`, `FileEntry`, `RemovalTarget`, `DiskInfo`, formatting helpers |
| `Scanner.swift` | Job-queue-based parallel folder scanner, protected path rules |
| `DuplicateFinder.swift` | Size → partial digest → SHA-256 duplicate detection |
| `SimilarPhotos.swift` | Similar photo grouping with Vision feature prints |
| `JunkScanner.swift` | Definitions and scanning of junk file categories |
| `SmartCleanup.swift` | Protection catalog, matching rules, Smart Cleanup levels and planner |
| `Rules.swift` | Auto Cleanup rules and `RuleEngine` |
| `Growth.swift` | Scan summaries (`SnapshotStore`) and comparison |
| `Archive.swift` | Copy to an external disk → verify → move to the Trash |
| `AppInventory.swift` | Installed apps and their `~/Library` leftovers |
| `StorageBreakdown.swift` | `Shell` helper, APFS volumes, Time Machine snapshots |
| `DevTools.swift`, `DockerService.swift` | Homebrew, simulators, Docker CLI integration |
| `Assistant.swift` | Rule-based recommendation engine and the assistant screen |
| `Monitor.swift` | Preferences, free-space monitor, notifications, menu bar, Settings |
| `ScreenshotMode.swift` | Automated mode that produces the documentation screenshots (only enabled by an environment variable) |
| `*View.swift`, `Components.swift`, `TreemapView.swift`, `SplashView.swift` | Screens and shared components |

## Scanner

`DiskScanner` is designed to scan large trees (e.g. the whole disk, millions of files) quickly and consistently.

1. **Job queue.** The root folder is put on a `JobQueue`. As many workers as there are cores (`DispatchQueue.concurrentPerform`) pull jobs from the queue.
2. **Shallow splitting, deep recursion.** For folders in the first 4 levels (`splitDepth`), only their own contents are read and their subfolders are queued as new jobs. Deeper folders are scanned recursively within a single job. This way a single huge folder (e.g. `~/Library`) can't confine the scan to one core, and the number of jobs doesn't explode.
3. **Bottom-up aggregation.** When the workers finish, split folders are sorted from deepest to the root and their sizes are added to their parents. This step is lock-free and single-threaded.
4. **Size measurement.** File size is the space actually allocated on disk (`totalFileAllocatedSize`). Sparse and compressed files are counted the way Finder counts them.
5. **Tracked files.** Files over 1 MB are listed separately for the large file, duplicate and similar photo analyses. Folders such as `node_modules`, `.venv` and `Pods` are marked as "developer artifacts".
6. **Cancellation and progress.** `ScanCoordinator` manages the cancellation flag and throttled progress updates.

For skipped virtual paths, protected roots and package detection, see [safety.md](safety.md#protections-during-scanning).

## Duplicate detection

```
all tracked files
  └─ group by size (unique sizes are dropped, hard links are de-duplicated)
       └─ digest of the first + last 64 KB (most candidates are eliminated here)
            └─ full SHA-256 (only for what remains)
```

Cloud-only iCloud files are not read (`SF_DATALESS` / no allocated blocks). Groups are sorted by wasted space.

## Concurrency model

- The package is compiled in Swift 5 language mode; `AppState` and the views are `@MainActor`.
- Long-running work is started with `Task.detached`, the task reference is kept, and `cancelScan()` cancels all of them.
- Engines run in the background and return only values (structs, ownership of a class tree) to the main actor. Progress callbacks are forwarded with `Task { @MainActor in … }`.
- Removal also runs in the background. The history and lists are updated on the main actor once the result arrives.

## Localization

- English is the **source language**. Every user-facing string in the code is English and goes through `L("…")` (a thin wrapper around `String(localized:)`), or is a SwiftUI string literal.
- Translations live in a single String Catalog, [`Resources/Localizable.xcstrings`](../Resources/Localizable.xcstrings). It also holds English plural variations ("1 file" / "2 files").
- `scripts/update-strings.sh` extracts every string with the compiler (`-emit-localized-strings`) and syncs new keys into the catalog. `LocalizationTests` fails if a key has no Turkish translation or if its format specifiers don't match.
- `build-app.sh` compiles the catalog with `xcstringstool` into `en.lproj` / `tr.lproj` inside the app bundle. Turkish permission prompts are in `Resources/tr.lproj/InfoPlist.strings`.
- The interface language is chosen in Settings. `AppLanguage.applyAtLaunch()` runs before SwiftUI starts and sets the app's `AppleLanguages` preference, so menus, alerts and formatters follow the same language. A change takes effect after a relaunch.

## Persistence

| Data | Mechanism |
|---|---|
| Settings, exclusions, protections, rules, scan scope, language | `UserDefaults` (`Prefs`, `@AppStorage`) |
| Cleanup history | JSON, `Paths.dataDirectory/history.json` |
| Scan summaries | JSON, `Paths.dataDirectory/snapshots/<SHA-256 prefix of the root path>.json` |

`Paths.home` and `Paths.dataDirectory` can be overridden with environment variables. Tests and screenshot generation use this (see [development.md](development.md#environment-variables)).

## Tests

The tests in `Tests/CleanMacTests` create real files in temporary folders and check:
- the scanner,
- the duplicate finder,
- the safe removal checks,
- restore,
- Smart Cleanup matching,
- rules,
- archiving,
- Docker output parsing,
- similar photos,
- rendering of the welcome screen,
- completeness of the string catalog.

The tests never touch the user's files. Tests that talk to the real system (Docker, benchmark) are enabled with an environment variable.

## Design decisions

- **No dependencies.** A deletion tool's supply-chain attack surface should be as small as possible. Everything is done with Apple frameworks.
- **No sandbox.** Required for disk analysis. Safety comes instead from the single removal path, the last-moment checks and the Trash-by-default rule.
- **A single removal path.** Whichever screen it comes from, every removal goes through `AppState.remove` and `safetyProblem`. New features must use this path.
- **Explain, then delete.** Every category and suggestion carries text that explains what happens if it is removed.
