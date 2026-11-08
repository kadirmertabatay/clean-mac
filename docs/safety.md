# Safety and Privacy

CleanMac deletes files. This document describes which safeguards are applied where, what is stored, and the known limitations, so that users and contributors can check against the code why the app is safe.

## Principles

1. **No deletion without confirmation.** Every deletion in the user interface goes through a confirmation dialog. The only exception is a rule for which the user explicitly chose "Apply without asking".
2. **Reversible by default.** Items are moved to the Trash with `FileManager.trashItem`, and their location in the Trash is recorded in the history.
3. **Re-check at the last moment.** The world may have changed between the scan and the removal, so every item is checked again right before it is removed.
4. **When in doubt, skip.** If a check is inconclusive, the item is not deleted and is reported as "skipped".
5. **No network.** The app makes no network requests and no data leaves the Mac.

## Removal flow

Every removal goes through a single path: `AppState.remove(_:permanently:)` ([AppState.swift](../Sources/CleanMac/AppState.swift)).

```
Screen (confirmation dialog)
   └─► list of RemovalTarget  (url, size, expected modification date, copies to keep)
         └─► safetyProblem(...) for each item  ── problem ──► skipped + reason
               └─► trashItem (default)  or  removeItem (only if permanent was chosen)
                     └─► HistoryRecord (original path, Trash path, size, date)
```

`safetyProblem` checks the following right before removal:

| Check | What it prevents |
|---|---|
| Is the path in the **exclusions** list or below it? | Something the user protected being deleted by any flow |
| Does the item still exist? (`lstat`, without following symlinks) | Acting on an item that was moved or already deleted |
| Is the modification date the same as at scan time? | Deleting a file that was worked on after the scan |
| (Duplicates) Does at least one of the copies to keep still exist? | Deleting the **last** copy of some content |

Smart Cleanup and Auto Cleanup additionally apply the **Smart Cleanup protections** while building the plan (`SmartPlanner.filter`, `AppState.isSmartProtected`).

## When is something deleted permanently?

Only in these cases:

- When the **"Delete junk files permanently"** setting is on. It is the same setting in Settings and at the bottom of the Junk Files screen, and it is off by default. While it is on, permanent deletion applies to:
  - items cleaned from the Junk Files screen,
  - the assistant's quick **Clean** buttons (only for "safe" categories),
  - the regenerable cache groups in a Smart Cleanup plan.
- When cleaning the **Trash** category, because emptying the Trash is permanent by nature.

These always go to the Trash:
- duplicates,
- large files,
- apps and their leftovers,
- the sources of archived files,
- the non-regenerable groups in Smart Cleanup (copies, project dependencies, downloads).

## Protections during scanning

- **Protected locations:** the following are marked "protected":
  - `/System`, `/usr`, `/bin`, `/sbin`, `/Library`, `/Applications`, `/opt`, `/etc`, `/private/var/db` and `/private/var/vm`,
  - anything whose path contains a `Library` folder (including `~/Library`),
  - the contents of folders macOS treats as packages (`.app`, `.photoslibrary` …).

  These are hidden from the large-file and duplicate lists by default; Smart Select and Smart Cleanup plans never select protected files.
- **Skipped paths:** `/Volumes` (external disks), `/System/Volumes` and virtual paths that show the disk a second time (`/.nofollow`, `/.resolve`, `/.vol`, `/dev`, `/net` …) are not scanned. This keeps totals from being counted twice and keeps external disks from being touched unintentionally.
- **Symbolic links are not followed.** The link itself is counted when measuring sizes.
- **iCloud:** cloud-only files (with no local copy) are never read, so computing a digest never triggers a download.
- **Hard links:** paths that point to the same inode are counted as one file and never shown as copies of each other.

## Smart Cleanup protections

Every protection the user picks (personal area, browser, app, developer area) is turned into a set of paths and keywords. An item is protected when:

1. its path matches the protection,
2. it **contains** a protected path (for example, `~/Library/Caches/Google` contains the Chrome cache),
3. one of its direct children matches the protection.

Rules 2 and 3 keep a protection from being bypassed by deleting a parent folder. Protections are stored in `UserDefaults` and shared by Smart Cleanup, Auto Cleanup and the assistant's quick clean buttons.

## Administrator privileges

The app runs without administrator privileges. The only exception is deleting local Time Machine snapshots (`tmutil deletelocalsnapshots`). The command is tried with normal privileges first; if that fails, it is run again through macOS's standard password dialog (`osascript … with administrator privileges`). Only the snapshot date reported by `tmutil` is added to the command.

## External commands

Some features run tools installed on the system. They are all called by full path with an argument list (no shell interpretation):

| Tool | Use |
|---|---|
| `diskutil`, `tmutil` | APFS volumes, snapshots |
| `brew` | `cleanup --dry-run`, `cleanup` |
| `xcrun simctl` | Listing and deleting unused simulators |
| `docker` | Listing (`--format json`), `rm`, `rmi`, `volume rm`, `builder prune`, virtual disk TRIM |

Docker deletions don't use `-f`: Docker refuses to remove images in use and attached volumes, and running containers are never listed for removal.

## Stored data

Everything is stored locally, in the user's account:

| What | Where |
|---|---|
| Cleanup history | `~/Library/Application Support/CleanMac/history.json` |
| Scan summaries ("What Grew?") | `~/Library/Application Support/CleanMac/snapshots/` (last 12 per scope) |
| Settings, exclusions, protections, rules, language | `UserDefaults` (`com.kadirmertabatay.cleanmac`) |

Scan summaries only contain folder sizes and the paths of large files; no file contents are stored. To delete everything:

```bash
rm -rf ~/Library/Application\ Support/CleanMac
defaults delete com.kadirmertabatay.cleanmac
```

## Known limitations

- The app is **not sandboxed**: to analyze the disk it can access everything the user can. macOS TCC permissions (Desktop, Documents, Full Disk Access) still apply.
- Releases are ad-hoc signed and not notarized. Building from source is the most reliable way to avoid having to trust a binary.
- "Last used" dates rely on access dates kept by macOS and on Spotlight. These are not always reliable; review files that look old before deleting them.
- Permanently deleted items can't be restored.

If you find a security issue, please follow the steps in [SECURITY.md](../SECURITY.md).
