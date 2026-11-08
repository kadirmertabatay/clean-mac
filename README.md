<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="CleanMac simgesi">
</p>

<h1 align="center">CleanMac</h1>

<p align="center">
  Mac'inin depolama alanını analiz eden, neyin yer kapladığını açıklayan ve<br>
  güvenle temizlemene yardım eden, <b>tamamen yerel</b> çalışan açık kaynaklı bir asistan.
</p>

<p align="center">
  <a href="https://github.com/kadirmertabatay/clean-mac/actions/workflows/ci.yml"><img src="https://github.com/kadirmertabatay/clean-mac/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/lisans-MIT-blue.svg" alt="MIT Lisansı"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/aray%C3%BCz-SwiftUI-0A84FF" alt="SwiftUI">
  <img src="https://img.shields.io/badge/ba%C4%9F%C4%B1ml%C4%B1l%C4%B1k-yok-brightgreen" alt="Harici bağımlılık yok">
</p>

<p align="center">
  <a href="#kurulum">Kurulum</a> ·
  <a href="#özellikler">Özellikler</a> ·
  <a href="#güvenlik-ilkeleri">Güvenlik</a> ·
  <a href="docs/README.md">Belgeler</a> ·
  <a href="CONTRIBUTING.md">Katkıda Bulun</a>
</p>

<p align="center">
  <img src="docs/images/assistant.png" width="900" alt="CleanMac Akıllı Asistan ekranı">
</p>

---

## Neden CleanMac?

- **Gizlilik önce gelir.** Uygulama hiçbir ağ isteği yapmaz: analitik yok, hesap yok, bulut yok. Tüm tarama ve karşılaştırmalar senin Mac'inde yapılır.
- **Silmeden önce anlatır.** Her öneri neyin, neden ve ne kadar yer kapladığını, silinirse ne olacağını söyler.
- **Geri alınabilir.** Varsayılan olarak her şey Çöp Kutusu'na gider ve Temizlik Geçmişi'nden tek tıkla eski yerine döner.
- **Son söz senin.** Akıllı Silme'de dokunulmayacak uygulamaları ve klasörleri (ör. "Chrome'a dokunma") sen seçersin. Bu korumalar tüm otomatik akışlarda geçerlidir.
- **Hafif ve yerel.** Saf SwiftUI, harici bağımlılık yok, tüm çekirdekleri kullanan paralel bir tarayıcı.

## Özellikler

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/smart-cleanup.png" alt="Akıllı Silme ekranı">
      <p><b>Akıllı Silme.</b> Önce neye dokunulmayacağını seç (Masaüstü, Chrome, proje bağımlılıkları…), sonra Güvenli / Dengeli / Kapsamlı düzeyde tek bir plan al. Neyin hangi koruma yüzünden atlandığı ayrıca gösterilir.</p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/treemap.png" alt="Klasör Gezgini treemap görünümü">
      <p><b>Klasör Gezgini.</b> Boyut ağacını liste ve halka grafik ya da treemap olarak gez. Çift tıklayarak içine gir, sağ tıklayarak Finder'da göster ya da Çöp Kutusu'na taşı.</p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <img src="docs/images/duplicates.png" alt="Tekrarlanan Dosyalar ekranı">
      <p><b>Tekrarlanan Dosyalar.</b> Boyut → baş/son özeti → tam SHA-256 ile birebir aynı dosyaları bulur. "Akıllı Seç" en eski kopyayı korur; bir gruptaki tüm kopyaların silinmesi engellenir.</p>
    </td>
    <td valign="top">
      <img src="docs/images/large-files.png" alt="Büyük Dosyalar ekranı">
      <p><b>Büyük Dosyalar.</b> Boyuta, türe, son kullanıma ve konuma göre sırala. "6+ ay kullanılmayan" filtresi ve harici diske doğrulamalı arşivleme.</p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <img src="docs/images/junk.png" alt="Gereksiz Dosyalar ekranı">
      <p><b>Gereksiz Dosyalar.</b> Önbellekler, günlükler, Xcode verileri, paket yöneticisi önbellekleri, kurulum dosyaları, eski indirmeler, iPhone yedekleri ve Çöp Kutusu. Her kategori güvenlik düzeyiyle etiketlenir.</p>
    </td>
    <td valign="top">
      <img src="docs/images/growth.png" alt="Ne Büyüdü? ekranı">
      <p><b>Ne Büyüdü?</b> Her taramanın özeti saklanır. Önceki taramaya göre büyüyen ve küçülen klasörleri, yeni ve kaybolan büyük dosyaları gösterir.</p>
    </td>
  </tr>
  <tr>
    <td valign="top">
      <img src="docs/images/similar-photos.png" alt="Benzer Fotoğraflar ekranı">
      <p><b>Benzer Fotoğraflar.</b> Seri çekimleri ve yeniden kaydedilmiş kopyaları Apple Vision görüntü parmak iziyle, tamamen cihaz üzerinde gruplar.</p>
    </td>
    <td valign="top">
      <img src="docs/images/storage.png" alt="Depolama Dökümü ekranı">
      <p><b>Depolama Dökümü.</b> APFS birimleri, macOS'un kendi boşaltabileceği alan, yerel Time Machine anlık görüntüleri ve taramanın göremediği alan.</p>
    </td>
  </tr>
</table>

Ayrıca:

| | |
|---|---|
| **Akıllı Asistan** | Tek tıkla tam analiz yapar ve önerileri öncelik sırasıyla sunar. |
| **Uygulamalar** | Uygulamaları `~/Library` içinde bıraktıkları dosyalarla birlikte kaldırır, uzun süredir açılmayanları gösterir. |
| **Geliştirici** | Homebrew temizliği, kullanılmayan Xcode simülatörleri, dokunulmamış projelerin `node_modules` / `.venv` klasörleri. |
| **Docker** | Docker yüklüyse görünür. İmaj, konteyner, birim ve derleme önbelleğini listeler. Etiketsiz, eski sürüm, kullanılmayan ve fazladan etiketleri bulur, sanal diski küçültür. |
| **Otomatik Temizlik** | Zamanlanmış kurallar (ör. haftalık önbellek temizliği). Varsayılan olarak önce önizleme ve bildirim gelir; uygulamak için senin onayın gerekir. |
| **Menü çubuğu** | Boş alanı üst barda gösterir, belirlediğin eşiğin altına düşünce bildirim gönderir. |
| **Geçmiş ve Hariç Tutulanlar** | Kaldırılan her öğenin kaydı ve geri alma. Hariç tutulanlar hiçbir zaman önerilmez ve silinmez. |

Tüm ekranların ayrıntılı anlatımı için: **[docs/features.md](docs/features.md)**

## Kurulum

### Hazır sürüm

1. [Releases](https://github.com/kadirmertabatay/clean-mac/releases) sayfasından `CleanMac-<sürüm>.zip` dosyasını indir ve aç.
2. `CleanMac.app` dosyasını **Uygulamalar** klasörüne taşı.
3. Uygulama bir Apple Developer ID ile değil, ad-hoc olarak imzalı. İlk açılışta macOS uyarı verirse uygulamaya **sağ tıkla › Aç** de. macOS 15 ve sonrasında **Sistem Ayarları › Gizlilik ve Güvenlik › Yine de Aç** düğmesini kullan.

> İndirdiğin dosyayı sürüm notlarındaki SHA-256 değeriyle doğrulayabilirsin: `shasum -a 256 CleanMac-<sürüm>.zip`

### Kaynaktan derleme

Gereksinimler: macOS 14 Sonoma veya üstü ve Xcode 15+ (ya da Xcode Komut Satırı Araçları, Swift 5.9+).

```bash
git clone https://github.com/kadirmertabatay/clean-mac.git
cd clean-mac
./build-app.sh            # build/CleanMac.app
open build/CleanMac.app

./build-app.sh --install  # ayrıca /Applications içine kopyalar
```

Geliştirme sırasında `swift run`, testler için `swift test`. Ayrıntılar: [docs/development.md](docs/development.md)

## Kullanım

1. **Akıllı Asistan** ekranında **Kapsam**'ı seç: *Ana Klasör (~)*, *Tüm Mac (/)* ya da *Farklı Klasör…*
2. **Tam Analizi Başlat**'a bas. Gereksiz dosyalar, klasör boyutları, tekrarlar, depolama dökümü ve uygulamalar tek seferde hesaplanır.
3. Önerileri incele. Her satırdaki düğme seni ilgili ekrana götürür ya da (yalnızca güvenli kategorilerde) doğrudan temizler.
4. Tek bir temizlik planı istersen **Akıllı Silme**'ye geç, korumalarını seç ve planı onayla.

Bir klasörü kalıcı olarak korumak için listelerde ona sağ tıkla › **Hariç Tut**.

## Güvenlik ilkeleri

CleanMac dosya silen bir araç olduğu için güvenlik, tasarımın merkezinde:

- **Onaysız silme yok.** Her işlemden önce özet ve onay penceresi gösterilir.
- **Varsayılan: Çöp Kutusu.** Kalıcı silme yalnızca açıkça seçilirse (ve Çöp Kutusu'nu boşaltırken) yapılır.
- **Son anda yeniden doğrulama.** Silmeden hemen önce her öğe yeniden kontrol edilir. Taramadan sonra değiştiyse, artık yoksa ya da hariç tutulduysa atlanır.
- **Tekrarlarda en az bir kopya kalır.** Silme anında korunan kopyanın hâlâ var olduğu doğrulanır. Sabit bağlantılar (hard link) kopya sayılmaz.
- **Korumalı alanlar.** Sistem klasörleri ve uygulama paketlerinin (`.app`, `.photoslibrary` …) içi, büyük dosya ve tekrar listelerinde varsayılan olarak gizlidir.
- **iCloud'a dokunmaz.** Yalnızca bulutta duran (yerelde olmayan) dosyalar okunmaz, böylece indirme tetiklenmez.
- **Dürüst durum.** Okunamayan konumlar "Temiz" değil "İzin yok" olarak gösterilir.

Tasarımın ayrıntıları için [docs/safety.md](docs/safety.md). Bir güvenlik açığı bulursan lütfen [SECURITY.md](SECURITY.md)'deki adımları izle.

## İzinler

| İzin | Neden | Gerekli mi? |
|---|---|---|
| Masaüstü / Belgeler / İndirilenler | Bu klasörlerin boyutunu hesaplamak | İlk taramada macOS sorar |
| Tam Disk Erişimi | Çöp Kutusu, Mail, iPhone yedekleri gibi korumalı konumları görmek | İsteğe bağlı; yoksa asistan hatırlatır |
| Bildirimler | Boş alan azaldığında ve otomatik temizlik onay beklediğinde haber vermek | İsteğe bağlı |
| Yönetici parolası | Yalnızca yerel Time Machine anlık görüntüsü silerken | İşlem anında sorulur |

Tam Disk Erişimi vermek için CleanMac'i **Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi** listesine ekle.

## Belgeler

| Belge | İçerik |
|---|---|
| [Özellikler](docs/features.md) | Her ekranın ayrıntılı anlatımı ve ekran görüntüleri |
| [Güvenlik ve Gizlilik](docs/safety.md) | Silme akışı, doğrulamalar, korumalar, saklanan veriler |
| [Mimari](docs/architecture.md) | Kod yapısı, tarayıcı tasarımı, eşzamanlılık modeli |
| [Geliştirme](docs/development.md) | Derleme, test, ortam değişkenleri, ekran görüntüleri, sürüm çıkarma |
| [SSS ve Sorun Giderme](docs/faq.md) | Sık sorulan sorular, izin sorunları, açılış uyarıları |

## Katkıda bulunma

Hata bildirimleri, öneriler ve pull request'ler memnuniyetle karşılanır. Başlamadan önce [CONTRIBUTING.md](CONTRIBUTING.md) ve [Davranış Kuralları](CODE_OF_CONDUCT.md) belgelerine göz at. Sürüm notları: [CHANGELOG.md](CHANGELOG.md)

## Lisans

CleanMac [MIT Lisansı](LICENSE) ile dağıtılır. © 2026 Kadir Mert Abatay

---

<details>
<summary><b>English summary</b></summary>

<br>

**CleanMac** is a free, open-source, fully local storage assistant for macOS 14+, written in SwiftUI with no third-party dependencies. It scans your home folder, the whole startup disk or any folder, explains what is using space and suggests safe clean-ups.

Features:
- a recommendations assistant
- a smart cleanup planner where you choose what must never be touched (e.g. Chrome or your Desktop)
- a folder explorer with treemap
- large-file and exact-duplicate (SHA-256) finders
- on-device similar-photo grouping with Apple Vision
- junk categories: caches, logs, Xcode data, package caches, installers, old downloads
- APFS storage breakdown and scan-to-scan growth history
- an app uninstaller that also removes leftovers
- developer and Docker clean-up
- scheduled rules and a menu bar monitor

The app makes no network requests. Items go to the Trash by default and can be restored from the history screen. Every item is re-checked right before removal. The interface is currently in Turkish; translations are welcome (see [CONTRIBUTING.md](CONTRIBUTING.md)).

Build with `./build-app.sh && open build/CleanMac.app`. Licensed under MIT.

</details>
