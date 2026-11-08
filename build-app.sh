#!/bin/bash
# Builds the CleanMac.app bundle.
#
#   ./build-app.sh            creates build/CleanMac.app
#   ./build-app.sh --install  also copies it to /Applications
#   ./build-app.sh --zip      builds a universal (arm64 + x86_64) app and build/CleanMac-<version>.zip for GitHub Releases
set -euo pipefail
cd "$(dirname "$0")"

# Release archives (--zip) are built as universal binaries for Apple silicon and Intel.
BUILD_FLAGS=(-c release)
[ "${1:-}" = "--zip" ] && BUILD_FLAGS+=(--arch arm64 --arch x86_64)

swift build "${BUILD_FLAGS[@]}"
[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift Resources/logo.png Resources

APP="build/CleanMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/CleanMac" "$APP/Contents/MacOS/CleanMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"

# Localizations: the string catalog becomes <lang>.lproj/Localizable.strings(dict); InfoPlist.strings are copied as is.
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
for lproj in Resources/*.lproj; do
    mkdir -p "$APP/Contents/Resources/$(basename "$lproj")"
    cp "$lproj"/* "$APP/Contents/Resources/$(basename "$lproj")/"
done

codesign --force --sign - "$APP"
echo "Ready: $APP"

case "${1:-}" in
    --install)
        rm -rf /Applications/CleanMac.app
        cp -R "$APP" /Applications/
        echo "Installed: /Applications/CleanMac.app"
        ;;
    --zip)
        VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
        ZIP="CleanMac-$VERSION.zip"
        rm -f "build/$ZIP"
        ditto -c -k --keepParent "$APP" "build/$ZIP"
        (cd build && shasum -a 256 "$ZIP" | tee "$ZIP.sha256")
        echo "Archive: build/$ZIP"
        ;;
esac
