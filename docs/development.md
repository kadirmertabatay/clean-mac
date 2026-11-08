# Development

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ or the Xcode Command Line Tools (`xcode-select --install`), Swift 5.9+

The project is a Swift package, so no Xcode project is needed. You can still open it in Xcode with `open Package.swift`.

## Building and running

```bash
swift build                 # debug build
swift run                   # runs the app without a bundle (English only, no icon or permission texts)
./build-app.sh              # build/CleanMac.app (release, ad-hoc signed, with translations)
open build/CleanMac.app
./build-app.sh --install    # also copies it to /Applications
./build-app.sh --release    # universal (arm64 + x86_64) build plus build/CleanMac.dmg, build/CleanMac-<version>.zip and build/SHA256SUMS.txt
```

`build-app.sh`:
1. builds in release mode,
2. generates `Resources/AppIcon.icns` with `scripts/make-icon.swift` if it's missing,
3. assembles the `.app` bundle,
4. compiles the string catalog into `en.lproj` / `tr.lproj` and copies `InfoPlist.strings`,
5. copies the license into the bundle,
6. signs it ad-hoc with `codesign --sign -`.

> Because the ad-hoc signature changes with every build, macOS may ask again for Desktop / Documents / Full Disk Access permissions after you rebuild.

## Tests

```bash
swift test                                  # all tests
swift test --filter SmartCleanupTests       # a single test class
```

The tests create and delete their own files in temporary folders and never touch your files.

Optional tests:

```bash
CLEANMAC_BENCH=1 swift test -c release --filter Benchmark   # read-only speed measurement on your home folder
CLEANMAC_DOCKER_TEST=1 swift test --filter testLiveDocker   # live test against a running Docker
```

The live Docker test pulls the `hello-world` image (needs network access). It only deletes the `cleanmac-test` tag, container and volume it creates; the pulled `hello-world` image stays.

## Environment variables

| Variable | Effect |
|---|---|
| `CLEANMAC_SCAN_ROOT=/folder` | Default scan scope |
| `CLEANMAC_HOME=/folder` | Use this folder instead of the home folder (junk, apps, protections). When set, only `<folder>/Applications` is read instead of `/Applications` |
| `CLEANMAC_DATA_DIR=/folder` | Folder for the history and scan summaries |
| `CLEANMAC_LANGUAGE=en\|tr\|system` | Overrides the interface language chosen in Settings |
| `CLEANMAC_SCREENSHOTS=/folder` | Enables screenshot mode (see below) |
| `CLEANMAC_SCREENSHOTS_APPEARANCE=light` | Generates screenshots in light mode (dark by default) |

Example: try the app with a fully isolated demo folder, in Turkish:

```bash
CLEANMAC_HOME=/tmp/demo CLEANMAC_SCAN_ROOT=/tmp/demo CLEANMAC_DATA_DIR=/tmp/demo-data CLEANMAC_LANGUAGE=tr \
  ./build/CleanMac.app/Contents/MacOS/CleanMac
```

## Translations

English is the source language. Every user-facing string is written in English in the code and wrapped in `L("…")`, or passed as a SwiftUI string literal (`Text("…")`, `Button("…")`). Translations are kept in `Resources/Localizable.xcstrings`.

When you add or change strings:

```bash
./scripts/update-strings.sh                 # extracts strings with the compiler and syncs the catalog
open Resources/Localizable.xcstrings        # add the Turkish translations in Xcode (or edit the JSON)
swift test --filter LocalizationTests       # fails if a translation is missing or its placeholders differ
```

Tips:

- Use interpolation instead of concatenation so translators can reorder words: `L("Move \(count) files to the Trash?")`, not `L("Move ") + "\(count)" + …`.
- Counted nouns get English plural variations in the catalog ("1 file" / "2 files"). Turkish doesn't need them.
- Strings that are only logged or used as identifiers (file names, keys) should not be wrapped in `L()`.
- In SwiftUI, `Text(L("…"))` shows the string verbatim. If it contains Markdown (`**bold**`, `` `code` ``), use `Text(.init(L("…")))`.

### Adding a language

1. Add the language code to `CFBundleLocalizations` in `Resources/Info.plist`.
2. Add a case to `AppLanguage` (with the language's name written in that language).
3. Add translations for the new language to `Localizable.xcstrings`, and an `InfoPlist.strings` file in `Resources/<code>.lproj/` for the permission prompts.
4. Extend `LocalizationTests` to check the new language.

## Screenshots

The images in `docs/images` are not taken by hand. One command regenerates them:

```bash
./scripts/screenshots.sh                               # English, into docs/images
CLEANMAC_LANGUAGE=tr ./scripts/screenshots.sh /tmp/tr  # Turkish, into another folder
```

The script:

1. Sets up a fake home folder in a temporary location: movies, downloads, caches, Xcode data, projects, similar photos and fake app bundles. The files are APFS clones, so their logical sizes look realistic but they only use ~1 GB on disk.
2. Builds the app, runs one scan and quits, changes the demo folder, then starts the app again in screenshot mode. This gives the "What Grew?" screen a previous scan to compare with.
3. The app resizes the window to 1280×820, moves it to the highest-resolution screen, runs the full analysis, visits each screen and captures it. Nothing is deleted. Changed settings are restored at the end.
4. The images are copied to the output folder and the temporary folder is deleted.

Notes:

- Don't touch the window while the screenshots are being taken; it takes about a minute.
- The app captures its own window, so no screen recording permission is needed.
- On a Retina display the images are 2x (2560×1640).
- The **Storage Breakdown** screen shows the real disk's volume information, which contains no personal data. The **Developer** and **Docker** screens show the output of real system tools, so they are left out of the script.

## Code style

- Interface text is short, clear and non-technical, and addresses the user directly ("you").
- Identifiers, comments and source strings are in English.
- When adding a new removal feature, **always** use `AppState.remove(_:permanently:)`. Don't call `FileManager.removeItem` / `trashItem` directly.
- Heavy work must not block the main actor. Use `Task.detached`, keep the task reference and support cancellation.
- If you add a new engine (scanning, analysis), write it as a pure type and test it with real files in a temporary folder.

## Releasing

Releases follow git flow (see [CONTRIBUTING.md](../CONTRIBUTING.md#branching-model)):

1. Start a release branch from `develop`:

   ```bash
   git switch develop && git pull
   git switch -c release/1.1.0
   ```

2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
3. Move the "Unreleased" entries in `CHANGELOG.md` under a new heading for the version and update the comparison links.
4. Run the tests (`swift test`) and refresh the screenshots if the UI changed (`./scripts/screenshots.sh`).
5. Merge the release branch into `main` and tag it, then merge it back into `develop`:

   ```bash
   git switch main && git merge --no-ff release/1.1.0
   git tag -a v1.1.0 -m "CleanMac 1.1.0"
   git switch develop && git merge --no-ff release/1.1.0
   git branch -d release/1.1.0
   git push origin main develop --tags
   ```

   With branch protection on, open pull requests from `release/1.1.0` into `main` and `develop` instead, and push only the tag.

6. Pushing the tag starts the `Release` workflow. It builds the universal app and creates a draft GitHub release with `CleanMac.dmg`, the zip and `SHA256SUMS.txt`; GitHub's generated release notes are grouped by pull request labels (`.github/release.yml`). Review the draft and publish it.

   To build and publish by hand instead: `./build-app.sh --release`, then `gh release create v1.1.0 build/CleanMac.dmg build/CleanMac-1.1.0.zip build/SHA256SUMS.txt --title "CleanMac 1.1.0"`.

   The DMG keeps the unversioned name `CleanMac.dmg` on purpose: the README links to `releases/latest/download/CleanMac.dmg`, which always serves the newest published (non-draft) release.

Hotfixes work the same way, but the branch (`hotfix/1.1.1`) starts from `main`.

## Repository settings

`./scripts/github-setup.sh` applies the GitHub settings in one go: description, topics, enabled features, labels (`.github/labels.json`), private vulnerability reporting, Dependabot alerts, and branch protection for `main` and `develop`. The social preview image (`docs/images/social-preview.png`, generated by `swift scripts/make-social-preview.swift`) has to be uploaded by hand under **Settings › General › Social preview**.

## Icon

`Resources/logo.png` is the source logo. Regenerate the icon with:

```bash
rm Resources/AppIcon.icns && swift scripts/make-icon.swift Resources/logo.png Resources
```

The script cleans up the logo's background, places it on a white squircle, and writes `AppIcon.icns` and `AppIcon-1024.png`.
