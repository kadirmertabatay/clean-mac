# Değişiklik Günlüğü

Bu projedeki önemli değişiklikler bu dosyada tutulur. Biçim [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/) önerisine, sürüm numaraları [Anlamsal Sürümleme](https://semver.org/lang/tr/) kurallarına uyar.

## [Yayınlanmadı]

## [1.0.0] - 2026-11-08

İlk herkese açık sürüm.

### Eklenenler

- **Akıllı Asistan:** tek tıkla tam analiz (gereksizler → klasör taraması → tekrarlar → depolama → uygulamalar) ve öncelik sıralı öneriler.
- **Akıllı Silme:** dokunulmayacak alanları, tarayıcıları, uygulamaları ve geliştirici alanlarını seçerek Güvenli / Dengeli / Kapsamlı temizlik planı. Korumalar Otomatik Temizlik ve hızlı temizlemede de geçerli.
- **Klasör Gezgini:** liste, halka grafik ve squarified treemap görünümleri.
- **Tarama kapsamı:** Ana Klasör, Tüm Mac (sanal ve harici yollar hariç) ya da herhangi bir klasör; tüm çekirdekleri kullanan iş kuyruklu tarayıcı.
- **Büyük Dosyalar:** filtreler, Hızlı Bakış ve harici diske SHA-256 doğrulamalı arşivleme.
- **Tekrarlanan Dosyalar:** boyut → kısmi özet → SHA-256; sabit bağlantı ve iCloud farkındalığı; son kopya koruması.
- **Benzer Fotoğraflar:** Apple Vision görüntü parmak iziyle cihaz üzerinde gruplama.
- **Gereksiz Dosyalar:** önbellekler, günlükler, Xcode verileri, paket yöneticisi önbellekleri, kurulum dosyaları, eski indirmeler, iPhone yedekleri, Çöp Kutusu, proje bağımlılıkları.
- **Depolama Dökümü:** APFS birimleri, temizlenebilir alan, yerel Time Machine anlık görüntülerini silme.
- **Ne Büyüdü?:** tarama özetleri ve önceki taramalarla karşılaştırma.
- **Uygulamalar:** Library kalıntılarıyla birlikte kaldırma ve son açılma tarihleri.
- **Geliştirici:** Homebrew temizliği, kullanılmayan simülatörler, dokunulmamış projelerin bağımlılıkları.
- **Docker:** imaj, konteyner, birim ve derleme önbelleği analizi, seçerek silme, sanal diski küçültme.
- **Otomatik Temizlik:** önizlemeli ve onaylı zamanlanmış kurallar.
- **Menü çubuğu:** boş alan göstergesi ve az alan bildirimleri.
- **Temizlik Geçmişi** ile geri alma ve **Hariç Tutulanlar**.
- Karşılama ekranı ve Ayarlar penceresi.
- Belgeler (`docs/`), ekran görüntüsü üretme betiği ve evrensel (arm64 + x86_64) sürüm paketleme.

[Yayınlanmadı]: https://github.com/kadirmertabatay/clean-mac/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kadirmertabatay/clean-mac/releases/tag/v1.0.0
