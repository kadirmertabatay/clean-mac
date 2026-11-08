## What changed?

<!-- Short description. Related issue: #… -->

## Why?

## How was it tested?

## Checklist

- [ ] `swift build` and `swift test` pass
- [ ] Tests were added or updated for behavior changes
- [ ] New code that removes files goes through `AppState.remove(_:permanently:)`
- [ ] New deletion flows show a confirmation and default to the Trash
- [ ] No network requests or third-party dependencies were added
- [ ] New user-facing strings are in the string catalog with a Turkish translation (`./scripts/update-strings.sh`)
- [ ] Screenshots are attached if the UI changed (`./scripts/screenshots.sh` if needed)
- [ ] `CHANGELOG.md` is updated
