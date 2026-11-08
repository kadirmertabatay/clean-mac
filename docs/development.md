# Geliştirme

## Gereksinimler

- macOS 14 Sonoma veya üstü
- Xcode 15+ ya da Xcode Komut Satırı Araçları (`xcode-select --install`), Swift 5.9+

Proje bir Swift paketi olduğu için Xcode projesi gerekmez. İstersen `Package.swift`'i Xcode ile açabilirsin (`open Package.swift`).

## Derleme ve çalıştırma

```bash
swift build                 # hata ayıklama derlemesi
swift run                   # uygulamayı paketlemeden çalıştırır (simge ve bazı izin metinleri olmadan)
./build-app.sh              # build/CleanMac.app (release, ad-hoc imzalı)
open build/CleanMac.app
./build-app.sh --install    # ayrıca /Applications içine kopyalar
./build-app.sh --zip        # evrensel (arm64 + x86_64) derleme, build/CleanMac-<sürüm>.zip ve SHA-256 dosyası
```

`build-app.sh` şunları yapar:
1. release derlemesi yapar,
2. `Resources/AppIcon.icns` yoksa `scripts/make-icon.swift` ile üretir,
3. `.app` paketini kurar,
4. lisansı pakete kopyalar,
5. `codesign --sign -` ile ad-hoc imzalar.

> Ad-hoc imza her derlemede değiştiği için macOS, yeniden derlemeden sonra Masaüstü / Belgeler / Tam Disk Erişimi izinlerini tekrar isteyebilir.

## Testler

```bash
swift test                                  # tüm testler
swift test --filter SmartCleanupTests       # tek bir test sınıfı
```

Testler geçici klasörlerde kendi dosyalarını oluşturur ve siler. Kullanıcının dosyalarına dokunmaz.

İsteğe bağlı testler:

```bash
CLEANMAC_BENCH=1 swift test -c release --filter Benchmark   # ana klasörde salt okunur hız ölçümü
CLEANMAC_DOCKER_TEST=1 swift test --filter testLiveDocker   # çalışan bir Docker ile canlı test
```

Canlı Docker testi `hello-world` imajını indirir (ağ gerektirir). Yalnızca kendi oluşturduğu `cleanmac-test` adlı etiketi, konteyneri ve birimi siler; indirilen `hello-world` imajı yerinde kalır.

## Ortam değişkenleri

| Değişken | Etki |
|---|---|
| `CLEANMAC_SCAN_ROOT=/klasör` | Varsayılan tarama kapsamı |
| `CLEANMAC_HOME=/klasör` | Ana klasör yerine bu klasörü kullan (gereksizler, uygulamalar, korumalar). Ayarlanırsa `/Applications` yerine yalnızca `<klasör>/Applications` okunur |
| `CLEANMAC_DATA_DIR=/klasör` | Geçmiş ve tarama özetlerinin tutulduğu klasör |
| `CLEANMAC_SCREENSHOTS=/klasör` | Ekran görüntüsü modunu açar (aşağıya bakın) |
| `CLEANMAC_SCREENSHOTS_APPEARANCE=light` | Ekran görüntülerini açık temada üretir (varsayılan koyu) |

Örnek: uygulamayı tamamen izole bir demo klasörüyle denemek için

```bash
CLEANMAC_HOME=/tmp/demo CLEANMAC_SCAN_ROOT=/tmp/demo CLEANMAC_DATA_DIR=/tmp/demo-data \
  ./build/CleanMac.app/Contents/MacOS/CleanMac
```

## Ekran görüntüleri

`docs/images` içindeki görüntüler elle alınmaz. Tek komutla yeniden üretilir:

```bash
./scripts/screenshots.sh
```

Betik şunları yapar:

1. Geçici bir klasörde sahte bir ana klasör kurar: filmler, indirmeler, önbellekler, Xcode verileri, projeler, benzer fotoğraflar ve sahte uygulama paketleri. Dosyalar APFS klonlarıyla üretildiği için mantıksal boyutları gerçekçidir ama diskte yalnızca ~1 GB yer kaplarlar.
2. Uygulamayı derler. Önce bir tarama yapıp kapatır, demo klasörünü değiştirir ve uygulamayı ekran görüntüsü moduyla tekrar açar. Böylece "Ne Büyüdü?" ekranında karşılaştırılacak bir önceki tarama olur.
3. Uygulama pencereyi 1280×820 boyutuna getirir ve en yüksek çözünürlüklü ekrana taşır. Ardından tam analizi çalıştırır, ekranları sırayla gezer ve her birinin görüntüsünü alır. Hiçbir şey silinmez. Değiştirilen ayarlar bitince geri yüklenir.
4. Görüntüler `docs/images` içine kopyalanır ve geçici klasör silinir.

Notlar:

- Görüntü alınırken pencereye dokunma; işlem yaklaşık bir dakika sürer.
- Uygulama kendi penceresini yakaladığı için ekran kaydı izni gerekmez.
- Retina ekran varsa görüntüler 2x (2560×1640) olur.
- **Depolama Dökümü** ekranı gerçek diskin birim bilgilerini gösterir; bunlar kişisel veri içermez. **Geliştirici** ve **Docker** ekranları gerçek sistem araçlarının çıktısını gösterdiği için betiğe dahil edilmez.

## Kod stili

- Arayüz metinleri Türkçedir ve kullanıcıya "sen" diye hitap eder. Kısa, açık ve teknik olmayan bir dil kullan.
- Kod tanımlayıcıları İngilizce, açıklama satırları Türkçedir.
- Yeni bir silme özelliği eklerken **her zaman** `AppState.remove(_:permanently:)` kullan. Doğrudan `FileManager.removeItem` / `trashItem` çağırma.
- Ağır işler ana aktörü bloklamamalı. `Task.detached` kullan, görev referansını sakla ve iptali destekle.
- Yeni bir motor (tarama, analiz) ekliyorsan onu saf bir tür olarak yaz ve geçici klasörde gerçek dosyalarla test et.

## Sürüm çıkarma

1. `Resources/Info.plist` içinde `CFBundleShortVersionString` ve `CFBundleVersion` değerlerini artır.
2. `CHANGELOG.md`'ye yeni sürümün başlığını ve değişiklikleri ekle.
3. Testleri çalıştır: `swift test`.
4. Gerekirse ekran görüntülerini yenile: `./scripts/screenshots.sh`.
5. Arşivi üret: `./build-app.sh --zip`. Sonuç `build/CleanMac-<sürüm>.zip` ve `.sha256` dosyasıdır.
6. Etiketle ve yayınla:

   ```bash
   git tag -a v1.0.0 -m "CleanMac 1.0.0"
   git push origin main --tags
   gh release create v1.0.0 build/CleanMac-1.0.0.zip --title "CleanMac 1.0.0" --notes-file <sürüm-notları>
   ```

   Sürüm notlarına `.sha256` dosyasındaki değeri ekle.

## Simge

`Resources/logo.png` kaynak logodur. Simge şu komutla yeniden üretilir:

```bash
rm Resources/AppIcon.icns && swift scripts/make-icon.swift Resources/logo.png Resources
```

Betik logonun arka planını temizler, beyaz bir squircle üzerine yerleştirir ve `AppIcon.icns` ile `AppIcon-1024.png` dosyalarını üretir.
