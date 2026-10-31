# CleanMac

Mac'in depolama alanını analiz eden ve temiz tutmana yardım eden, tamamen yerel çalışan bir SwiftUI uygulaması. İnternete hiçbir veri gönderilmez.

## Özellikler

| Bölüm | Ne yapar |
|---|---|
| **Akıllı Asistan** | Tek tıkla tam analiz (gereksiz dosyalar → klasör taraması → tekrarlar) yapar ve öncelik sırasına göre öneriler sunar: disk doluluğu, temizlenebilir önbellekler, uzun süredir kullanılmayan büyük dosyalar, tekrarlar, proje bağımlılıkları |
| **Genel Bakış** | Disk doluluğu, özet kartlar, en büyük klasörler |
| **Klasör Gezgini** | Seçilen klasörün boyut ağacı; çift tıkla içine gir, halka grafikle dağılımı gör, sağ tık ile Finder'da göster / çöpe taşı |
| **Büyük Dosyalar** | Boyut, tür, son kullanım ve konuma göre sıralanabilen tablo; "6+ ay kullanılmayan" filtresi |
| **Tekrarlanan Dosyalar** | Boyut → baş/son 64 KB özeti → tam SHA-256 ile birebir aynı dosyaları bulur. "Akıllı Seç" en eski kopyayı korur |
| **Gereksiz Dosyalar** | Önbellekler, loglar, Xcode DerivedData / DeviceSupport / Archives, npm-pnpm-Gradle-Cargo-Bun-Go önbellekleri, `~/.cache`, İndirilenler'deki kurulum dosyaları, eski indirmeler, iPhone yedekleri, Çöp Kutusu, `node_modules` / `.venv` / `Pods` klasörleri |

## Güvenlik ilkeleri

- Hiçbir dosya onayın olmadan silinmez; her silme işleminden önce özet gösterilir.
- Varsayılan olarak her şey **Çöp Kutusu'na taşınır** (geri alınabilir). Kalıcı silme yalnızca Gereksiz Dosyalar ekranındaki seçenekle ve Çöp Kutusu'nu boşaltırken yapılır.
- `~/Library`, sistem klasörleri ve uygulama paketlerinin (`.app`, `.photoslibrary` …) içindeki dosyalar "korumalı" sayılır, büyük dosya ve tekrar listelerinde varsayılan olarak gizlenir.
- Tekrarlarda bir gruptaki tüm kopyaları silmek engellenir; sabit bağlantılar (hard link) kopya sayılmaz.
- iCloud'da tutulup yerelde olmayan dosyalar okunmaz (indirme tetiklenmez).

## Derleme ve çalıştırma

Gereksinim: macOS 14+, Xcode komut satırı araçları (Swift 5.9+).

```bash
./build-app.sh            # build/CleanMac.app oluşturur
./build-app.sh --install  # ayrıca /Applications içine kopyalar
open build/CleanMac.app
```

Geliştirme sırasında: `swift run` · Testler: `swift test`

İsteğe bağlı testler:

```bash
CLEANMAC_BENCH=1 swift test -c release --filter Benchmark   # ana klasörde salt okunur hız ölçümü
CLEANMAC_TRASH_TEST=1 swift test                            # Çöp Kutusu'na taşıma testi (çöpe küçük bir test dosyası bırakır)
```

`CLEANMAC_SCAN_ROOT=/bir/klasör` ortam değişkeni varsayılan tarama klasörünü değiştirir.

## İzinler

- İlk taramada macOS, Masaüstü / Belgeler / İndirilenler erişimi için izin isteyebilir.
- Çöp Kutusu, Mail, iPhone yedekleri gibi konumları görmek için **Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi** listesine CleanMac'i ekle (isteğe bağlı). Asistan bu izni yoksa hatırlatır.
- Uygulama ad-hoc imzalıdır; yeniden derledikten sonra macOS izinleri tekrar sorabilir.

## Proje yapısı

```
Sources/CleanMac/
  CleanMacApp.swift      Uygulama girişi, kenar çubuğu, menü komutları
  AppState.swift         Merkezi durum: tarama, tekrar arama, temizlik, silme
  Scanner.swift          Paralel klasör tarayıcı (boyut ağacı + büyük dosyalar)
  DuplicateFinder.swift  SHA-256 ile tekrar bulma
  JunkScanner.swift      Bilinen gereksiz dosya konumları
  Assistant.swift        Kural tabanlı öneri motoru + asistan ekranı
  *View.swift            Diğer ekranlar
scripts/make-icon.swift  Uygulama simgesini üretir
```
