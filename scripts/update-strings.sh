#!/bin/bash
# Extracts every localizable string from the code and syncs it into Resources/Localizable.xcstrings.
#
#   ./scripts/update-strings.sh
#
# New strings are added to the catalog (English is the source language); strings that are no longer used are
# marked stale. Add the Turkish translation for new keys in Xcode (open the .xcstrings file) or by editing the
# JSON, then run `swift test --filter LocalizationTests` to check that nothing is missing.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "› Extracting strings (clean build)…"
swift build --product CleanMac --scratch-path "$TMP/build" \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$TMP" >/dev/null

xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata "$TMP"/*.stringsdata
echo "✓ Resources/Localizable.xcstrings updated"
