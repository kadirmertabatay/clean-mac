#!/bin/bash
# CleanMac.app paketini derler.
#
#   ./build-app.sh            build/CleanMac.app oluşturur
#   ./build-app.sh --install  ayrıca /Applications içine kopyalar
#   ./build-app.sh --zip      evrensel (arm64 + x86_64) derler ve GitHub Releases için build/CleanMac-<sürüm>.zip üretir
set -euo pipefail
cd "$(dirname "$0")"

# Sürüm arşivi (--zip) hem Apple Silicon hem Intel için evrensel derlenir.
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
codesign --force --sign - "$APP"
echo "Hazır: $APP"

case "${1:-}" in
    --install)
        rm -rf /Applications/CleanMac.app
        cp -R "$APP" /Applications/
        echo "Kuruldu: /Applications/CleanMac.app"
        ;;
    --zip)
        VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
        ZIP="CleanMac-$VERSION.zip"
        rm -f "build/$ZIP"
        ditto -c -k --keepParent "$APP" "build/$ZIP"
        (cd build && shasum -a 256 "$ZIP" | tee "$ZIP.sha256")
        echo "Arşiv: build/$ZIP"
        ;;
esac
