#!/bin/bash
# Builds the CleanMac.app bundle.
#
#   ./build-app.sh            creates build/CleanMac.app
#   ./build-app.sh --install  also copies it to /Applications
#   ./build-app.sh --release  builds a universal (arm64 + x86_64) app plus the GitHub Release assets:
#                             build/CleanMac.dmg (drag-to-Applications installer), build/CleanMac-<version>.zip
#                             and build/SHA256SUMS.txt
set -euo pipefail
cd "$(dirname "$0")"

# Release builds are universal binaries for Apple silicon and Intel.
BUILD_FLAGS=(-c release)
case "${1:-}" in --release|--zip) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;; esac

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
    --release|--zip)
        VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
        ZIP="CleanMac-$VERSION.zip"
        DMG="CleanMac.dmg"   # unversioned, so releases/latest/download/CleanMac.dmg always points to the newest version
        rm -f "build/$ZIP" "build/$DMG" build/SHA256SUMS.txt

        ditto -c -k --keepParent "$APP" "build/$ZIP"

        # DMG: the app next to an Applications shortcut, with the CleanMac icon on the mounted volume.
        STAGE="$(mktemp -d)"
        trap 'rm -rf "$STAGE"' EXIT
        mkdir "$STAGE/root"
        cp -R "$APP" "$STAGE/root/"
        ln -s /Applications "$STAGE/root/Applications"
        cp Resources/AppIcon.icns "$STAGE/root/.VolumeIcon.icns"
        hdiutil create -quiet -volname "CleanMac $VERSION" -srcfolder "$STAGE/root" -fs HFS+ -format UDRW -ov "$STAGE/rw.dmg"
        MOUNT="$(hdiutil attach -nobrowse -noautoopen "$STAGE/rw.dmg" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
        if [ -n "$MOUNT" ] && command -v SetFile >/dev/null; then SetFile -a C "$MOUNT"; fi
        [ -n "$MOUNT" ] && hdiutil detach -quiet "$MOUNT"
        hdiutil convert -quiet "$STAGE/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "build/$DMG"

        (cd build && shasum -a 256 "$DMG" "$ZIP" | tee SHA256SUMS.txt)
        echo "Release assets: build/$DMG, build/$ZIP, build/SHA256SUMS.txt"
        ;;
esac
