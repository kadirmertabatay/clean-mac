#!/bin/bash
# Belgelerdeki ekran görüntülerini (docs/images/*.png) sahte bir demo ana klasörüyle yeniden üretir.
#
#   ./scripts/screenshots.sh            # görüntüleri docs/images içine yazar
#   ./scripts/screenshots.sh /bir/klasör
#
# Gerçek dosyalarına dokunulmaz ve görüntülere girmez: uygulama CLEANMAC_HOME ile geçici bir demo
# klasörüne yönlendirilir, geçmiş/özetler CLEANMAC_DATA_DIR ile ayrı tutulur, hiçbir şey silinmez.
# Demo dosyaları APFS klonlarıyla üretildiği için diskte yalnızca ~1 GB yer kaplar; iş bitince silinir.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="${1:-$ROOT/docs/images}"
DEMO="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cleanmac-demo.XXXXXX")" && pwd -P)"   # /var → /private/var
H="$DEMO/home"
trap 'rm -rf "$DEMO"' EXIT

MiB=1048576
BASE="$DEMO/base.bin"
echo "› Demo verisi hazırlanıyor: $DEMO"
dd if=/dev/urandom of="$BASE" bs=$MiB count=1024 status=none

# mk <yol> <MiB> [YYYYMMDDhhmm]: 1 GB'lık rastgele tabanı klonlayıp keser, başını ve sonunu benzersiz yapar.
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

# Kişisel klasörler
mk "Movies/Tatil 2024 - 4K.mov" 900 202407201030
mk "Movies/Ekran Kaydı 2025-03-14.mov" 640 202503141215
mk "Movies/Düğün Kurgu Final.mp4" 780 202409081900
mk "Music/Podcast Arşivi/Bölüm 01-40.zip" 520 202402010900
mk "Documents/Proje Raporu.pdf" 46 202510011200
mk "Documents/Tez/Tez Final.docx" 22 202506151000
mk "Documents/Muhasebe 2025.numbers" 14 202511010900
mk "Desktop/Sunum Taslak.key" 160 202511051400
dup "Movies/Tatil 2024 - 4K.mov" "Desktop/Tatil 2024 - 4K kopya.mov"
dup "Movies/Düğün Kurgu Final.mp4" "Downloads/Düğün Kurgu Final (1).mp4"
dup "Documents/Proje Raporu.pdf" "Documents/Yedek/Proje Raporu.pdf"
dup "Documents/Proje Raporu.pdf" "Downloads/Proje Raporu.pdf"

# İndirilenler: kurulum dosyaları ve eski indirmeler
mk "Downloads/Xcode_16.dmg" 1000 202409200800
mk "Downloads/Docker.dmg" 560 202501100900
mk "Downloads/node-v22.11.0.pkg" 82 202511020900
mk "Downloads/ubuntu-24.04-desktop-arm64.iso" 1000 202304120900
mk "Downloads/Veri Seti (ham).zip" 700 202306031000
mk "Downloads/Fatura_Ekim.pdf" 2 202511030900

# Library: önbellekler, loglar, Xcode
mk "Library/Caches/Google/Chrome/Default/Cache/data_1" 620
mk "Library/Caches/com.spotify.client/Data/storage.bin" 410
mk "Library/Caches/com.tinyspeck.slackmacgap/Cache.db" 230
mk "Library/Caches/com.microsoft.VSCode.ShipIt/update.zip" 180
mk "Library/Caches/com.figma.Desktop/cache.bin" 96
mk "Library/Logs/DiagnosticReports/app.ips" 40
mk "Library/Logs/CoreSimulator/sim.log" 64
mk "Library/Developer/Xcode/DerivedData/HavaDurumu-abcdefg/Build/Intermediates.noindex/obj.o" 860
mk "Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 17.5 (21F79)/Symbols/dyld_shared_cache" 1000
mk ".npm/_cacache/content-v2/sha512/3f/a1/typescript-5.6.3.tgz" 380
mk ".cache/pip/wheels/torch-2.5.1-cp312-none-macosx_11_0_arm64.whl" 210
mk ".Trash/eski-ekran-goruntuleri.zip" 120

# Projeler: biri uzun süredir dokunulmamış, biri aktif
for p in "eski-blog:202402011200" "ml-deneme:202405101200" "hava-durumu-app:202511061200"; do
    name=${p%%:*}; stamp=${p##*:}
    mkdir -p "$H/Developer/$name"
    echo '{ "name": "'"$name"'" }' > "$H/Developer/$name/package.json"
    touch -t "$stamp" "$H/Developer/$name/package.json" "$H/Developer/$name"
done
mk "Developer/eski-blog/node_modules/@next/swc-darwin-arm64/next-swc.darwin-arm64.node" 430 202402011200
mk "Developer/ml-deneme/.venv/lib/python3.12/site-packages/torch/lib/libtorch_cpu.dylib" 940 202405101200
mk "Developer/hava-durumu-app/node_modules/@esbuild/darwin-arm64/bin/esbuild" 260 202511061200

# Benzer fotoğraflar: logonun yeniden boyutlandırılmış / kırpılmış / sıkıştırılmış kopyaları
mkdir -p "$H/Pictures/iPhone"
P="$H/Pictures/iPhone"
sips -s format png -Z 4032 Resources/logo.png --out "$P/IMG_2041.png" >/dev/null
sips -s format png -Z 3600 Resources/logo.png --out "$P/IMG_2042.png" >/dev/null
sips -s format png -Z 3024 Resources/logo.png --out "$P/IMG_2043.png" >/dev/null
sips -c 1500 1500 Resources/logo.png --out "$DEMO/crop.png" >/dev/null
sips -s format png -Z 3024 "$DEMO/crop.png" --out "$P/IMG_2044.png" >/dev/null
touch -t 202508161842 "$P"/IMG_*

# Uygulamalar (sahte paketler; simgeler yüklüyse gerçek uygulamadan kopyalanır)
fakeapp() {
    local name=$1 bid=$2 version=$3 size=$4 app="$H/Applications/$1.app"   # $5: kaç gün önce açıldı
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
    cp /usr/bin/true "$app/Contents/MacOS/$name"   # geçerli bir çalıştırılabilir dosya; yoksa Finder "açılamaz" simgesi gösterir
    mk "Applications/$name.app/Contents/Frameworks/$name Framework.dylib" "$size"
    touch -t "$(date -v-"$5"d +%Y%m%d%H%M)" "$app"   # "son açılma" tarihi buna düşer
}
fakeapp "Google Chrome" com.google.Chrome 131.0 520 0
fakeapp "Visual Studio Code" com.microsoft.VSCode 1.95 380 1
fakeapp "Slack" com.tinyspeck.slackmacgap 4.41 290 3
fakeapp "Spotify" com.spotify.client 1.2.50 210 64
fakeapp "Figma" com.figma.Desktop 124.6 260 214
fakeapp "Firefox" org.mozilla.firefox 132.0 240 410

echo "› Uygulama derleniyor"
./build-app.sh >/dev/null
BIN="$ROOT/build/CleanMac.app/Contents/MacOS/CleanMac"
export CLEANMAC_HOME="$H" CLEANMAC_SCAN_ROOT="$H" CLEANMAC_DATA_DIR="$DEMO/data" CLEANMAC_SCREENSHOTS="$DEMO/shots"
pkill -x CleanMac 2>/dev/null || true

echo "› Önceki tarama oluşturuluyor (Ne Büyüdü? için)"
CLEANMAC_SCREENSHOTS_WARMUP=1 "$BIN" >/dev/null 2>&1
# Taramalar arasında olan değişiklikler
mk "Downloads/Final Kurgu 2025.mov" 850 202511071800
mk "Library/Developer/Xcode/DerivedData/HavaDurumu-abcdefg/Build/Products/app.o" 300
rm -rf "$H/Music/Podcast Arşivi"

echo "› Ekran görüntüleri alınıyor (pencereye dokunma, ~1 dk)"
"$BIN" 2>/dev/null | grep '^screenshots:' || true

mkdir -p "$OUT"
cp "$DEMO"/shots/*.png "$OUT"/
echo "✓ $(ls "$DEMO"/shots/*.png | wc -l | tr -d ' ') görüntü → $OUT"
