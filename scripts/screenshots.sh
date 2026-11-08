#!/bin/bash
# Regenerates the documentation screenshots (docs/images/*.png) from a fake demo home folder.
#
#   ./scripts/screenshots.sh                                # writes the images to docs/images (English UI)
#   ./scripts/screenshots.sh /some/folder                   # writes them elsewhere
#   CLEANMAC_LANGUAGE=tr ./scripts/screenshots.sh /tmp/tr   # Turkish UI
#
# Your real files are never touched and never appear in the images: the app is pointed at a temporary demo
# folder with CLEANMAC_HOME, history and summaries are kept apart with CLEANMAC_DATA_DIR, and nothing is deleted.
# The demo files are APFS clones, so they only use ~1 GB on disk; they are removed when the script finishes.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="${1:-$ROOT/docs/images}"
DEMO="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cleanmac-demo.XXXXXX")" && pwd -P)"   # /var → /private/var
H="$DEMO/home"
trap 'rm -rf "$DEMO"' EXIT

MiB=1048576
BASE="$DEMO/base.bin"
echo "› Preparing demo data: $DEMO"
dd if=/dev/urandom of="$BASE" bs=$MiB count=1024 status=none

# mk <path> <MiB> [YYYYMMDDhhmm]: clones the 1 GB random base file, truncates it and makes its head and tail unique.
mk() {
    local path="$H/$1" size=$2 stamp=${3:-}
    mkdir -p "$(dirname "$path")"
    cp -c "$BASE" "$path"
    truncate -s $((size * MiB)) "$path"
    dd if=/dev/urandom of="$path" bs=65536 count=1 conv=notrunc status=none
    dd if=/dev/urandom of="$path" bs=65536 count=1 seek=$(( size * 16 - 1 )) conv=notrunc status=none
    if [ -n "$stamp" ]; then touch -t "$stamp" "$path"; fi
}
dup() { mkdir -p "$(dirname "$H/$2")"; cp -c "$H/$1" "$H/$2"; touch -r "$H/$1" "$H/$2"; }

# Personal folders
mk "Movies/Vacation 2024 - 4K.mov" 900 202407201030
mk "Movies/Screen Recording 2025-03-14.mov" 640 202503141215
mk "Movies/Wedding Edit Final.mp4" 780 202409081900
mk "Music/Podcast Archive/Episodes 01-40.zip" 520 202402010900
mk "Documents/Project Report.pdf" 46 202510011200
mk "Documents/Thesis/Thesis Final.docx" 22 202506151000
mk "Documents/Budget 2025.numbers" 14 202511010900
mk "Desktop/Presentation Draft.key" 160 202511051400
dup "Movies/Vacation 2024 - 4K.mov" "Desktop/Vacation 2024 - 4K copy.mov"
dup "Movies/Wedding Edit Final.mp4" "Downloads/Wedding Edit Final (1).mp4"
dup "Documents/Project Report.pdf" "Documents/Backup/Project Report.pdf"
dup "Documents/Project Report.pdf" "Downloads/Project Report.pdf"

# Downloads: installers and old downloads
mk "Downloads/Xcode_16.dmg" 1000 202409200800
mk "Downloads/Docker.dmg" 560 202501100900
mk "Downloads/node-v22.11.0.pkg" 82 202511020900
mk "Downloads/ubuntu-24.04-desktop-arm64.iso" 1000 202304120900
mk "Downloads/Dataset (raw).zip" 700 202306031000
mk "Downloads/Invoice_October.pdf" 2 202511030900

# Library: caches, logs, Xcode
mk "Library/Caches/Google/Chrome/Default/Cache/data_1" 620
mk "Library/Caches/com.spotify.client/Data/storage.bin" 410
mk "Library/Caches/com.tinyspeck.slackmacgap/Cache.db" 230
mk "Library/Caches/com.microsoft.VSCode.ShipIt/update.zip" 180
mk "Library/Caches/com.figma.Desktop/cache.bin" 96
mk "Library/Logs/DiagnosticReports/app.ips" 40
mk "Library/Logs/CoreSimulator/sim.log" 64
mk "Library/Developer/Xcode/DerivedData/WeatherApp-abcdefg/Build/Intermediates.noindex/obj.o" 860
mk "Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 17.5 (21F79)/Symbols/dyld_shared_cache" 1000
mk ".npm/_cacache/content-v2/sha512/3f/a1/typescript-5.6.3.tgz" 380
mk ".cache/pip/wheels/torch-2.5.1-cp312-none-macosx_11_0_arm64.whl" 210
mk ".Trash/old-screenshots.zip" 120

# Projects: two untouched for a long time, one active
for p in "old-blog:202402011200" "ml-experiment:202405101200" "weather-app:202511061200"; do
    name=${p%%:*}; stamp=${p##*:}
    mkdir -p "$H/Developer/$name"
    echo '{ "name": "'"$name"'" }' > "$H/Developer/$name/package.json"
    touch -t "$stamp" "$H/Developer/$name/package.json" "$H/Developer/$name"
done
mk "Developer/old-blog/node_modules/@next/swc-darwin-arm64/next-swc.darwin-arm64.node" 430 202402011200
mk "Developer/ml-experiment/.venv/lib/python3.12/site-packages/torch/lib/libtorch_cpu.dylib" 940 202405101200
mk "Developer/weather-app/node_modules/@esbuild/darwin-arm64/bin/esbuild" 260 202511061200

# Similar photos: resized / cropped copies of the logo
mkdir -p "$H/Pictures/iPhone"
P="$H/Pictures/iPhone"
sips -s format png -Z 4032 Resources/logo.png --out "$P/IMG_2041.png" >/dev/null
sips -s format png -Z 3600 Resources/logo.png --out "$P/IMG_2042.png" >/dev/null
sips -s format png -Z 3024 Resources/logo.png --out "$P/IMG_2043.png" >/dev/null
sips -c 1500 1500 Resources/logo.png --out "$DEMO/crop.png" >/dev/null
sips -s format png -Z 3024 "$DEMO/crop.png" --out "$P/IMG_2044.png" >/dev/null
touch -t 202508161842 "$P"/IMG_*

# Apps (fake bundles; icons are copied from the real app if it is installed)
fakeapp() {
    local name=$1 bid=$2 version=$3 size=$4 app="$H/Applications/$1.app"   # $5: opened this many days ago
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$name</string>
<key>CFBundleIdentifier</key><string>$bid</string>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
    local real="/Applications/$name.app"
    if [ -d "$real" ]; then
        local icon; icon=$(defaults read "$real/Contents/Info" CFBundleIconFile 2>/dev/null || true)
        icon=${icon%.icns}
        [ -n "$icon" ] && [ -f "$real/Contents/Resources/$icon.icns" ] && cp "$real/Contents/Resources/$icon.icns" "$app/Contents/Resources/AppIcon.icns"
    fi
    [ -f "$app/Contents/Resources/AppIcon.icns" ] || cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns "$app/Contents/Resources/AppIcon.icns"
    cp /usr/bin/true "$app/Contents/MacOS/$name"   # a valid executable; otherwise Finder shows the "can't open" icon
    mk "Applications/$name.app/Contents/Frameworks/$name Framework.dylib" "$size"
    touch -t "$(date -v-"$5"d +%Y%m%d%H%M)" "$app"   # the "last opened" date falls back to this
}
fakeapp "Google Chrome" com.google.Chrome 131.0 520 0
fakeapp "Visual Studio Code" com.microsoft.VSCode 1.95 380 1
fakeapp "Slack" com.tinyspeck.slackmacgap 4.41 290 3
fakeapp "Spotify" com.spotify.client 1.2.50 210 64
fakeapp "Figma" com.figma.Desktop 124.6 260 214
fakeapp "Firefox" org.mozilla.firefox 132.0 240 410

echo "› Building the app"
./build-app.sh >/dev/null
BIN="$ROOT/build/CleanMac.app/Contents/MacOS/CleanMac"
export CLEANMAC_HOME="$H" CLEANMAC_SCAN_ROOT="$H" CLEANMAC_DATA_DIR="$DEMO/data" CLEANMAC_SCREENSHOTS="$DEMO/shots"
export CLEANMAC_LANGUAGE="${CLEANMAC_LANGUAGE:-en}"
LOCALE_ARGS=(-AppleLocale "$([ "$CLEANMAC_LANGUAGE" = tr ] && echo tr_TR || echo en_US)")
pkill -x CleanMac 2>/dev/null || true

echo "› Creating a previous scan (for What Grew?)"
CLEANMAC_SCREENSHOTS_WARMUP=1 "$BIN" "${LOCALE_ARGS[@]}" >/dev/null 2>&1
# Changes between the two scans
mk "Downloads/Final Cut 2025.mov" 850 202511071800
mk "Library/Developer/Xcode/DerivedData/WeatherApp-abcdefg/Build/Products/app.o" 300
rm -rf "$H/Music/Podcast Archive"

echo "› Taking screenshots (don't touch the window, ~1 min)"
"$BIN" "${LOCALE_ARGS[@]}" 2>/dev/null | grep '^screenshots:' || true

mkdir -p "$OUT"
cp "$DEMO"/shots/*.png "$OUT"/
echo "✓ $(ls "$DEMO"/shots/*.png | wc -l | tr -d ' ') images → $OUT"
