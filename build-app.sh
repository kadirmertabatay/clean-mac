#!/bin/bash
# CleanMac.app paketini derler: ./build-app.sh  (kurmak için: ./build-app.sh --install)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift Resources/logo.png Resources

APP="build/CleanMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/CleanMac" "$APP/Contents/MacOS/CleanMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Hazır: $APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf /Applications/CleanMac.app
    cp -R "$APP" /Applications/
    echo "Kuruldu: /Applications/CleanMac.app"
fi
