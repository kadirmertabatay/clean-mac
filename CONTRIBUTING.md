# Katkıda Bulunma Rehberi

CleanMac'e ilgin için teşekkürler! Hata bildirimleri, öneriler, çeviriler, belgeler ve kod katkıları memnuniyetle karşılanır.

Katılarak [Davranış Kuralları](CODE_OF_CONDUCT.md)'na uymayı kabul etmiş olursun.

## Nasıl yardım edebilirim?

- **Hata bildir.** [Issues](https://github.com/kadirmertabatay/clean-mac/issues) sayfasında "Hata bildirimi" şablonunu kullan. macOS sürümünü, CleanMac sürümünü ve adımları yaz.
- **Özellik öner.** "Özellik önerisi" şablonuyla neyi neden istediğini anlat.
- **Çeviri yap.** Arayüz şu an Türkçe. Yerelleştirme altyapısı (String Catalog) ve İngilizce çeviri en çok istenen katkılardan.
- **Belgeleri iyileştir.** `docs/` altındaki her şey düzenlenebilir.
- **Kod yaz.** "good first issue" etiketli konular iyi bir başlangıç.

> **Güvenlik açıklarını herkese açık issue olarak bildirme.** Bunun için [SECURITY.md](SECURITY.md)'deki adımları izle.

## Geliştirme ortamı

```bash
git clone https://github.com/kadirmertabatay/clean-mac.git
cd clean-mac
swift build
swift test
./build-app.sh && open build/CleanMac.app
```

Ayrıntılar (ortam değişkenleri, demo klasörüyle izole çalıştırma, ekran görüntüleri) için: [docs/development.md](docs/development.md). Kodun nasıl düzenlendiği için: [docs/architecture.md](docs/architecture.md).

## Pull request süreci

1. Büyük bir değişiklikten önce bir issue açıp yaklaşımı konuşalım; boşa emek harcanmasın.
2. `main` dalından yeni bir dal aç: `git switch -c ozellik/kisa-aciklama`.
3. Değişikliği küçük, odaklı commit'lerle yap. Commit mesajları İngilizce ve emir kipinde olsun: `Add …`, `Fix …`.
4. Davranışı değiştiren her şey için test ekle ya da güncelle. `swift test` temiz geçmeli.
5. Arayüzü değiştirdiysen PR açıklamasına ekran görüntüsü ekle. Gerekirse `./scripts/screenshots.sh` ile `docs/images`'ı yenile.
6. Kullanıcıyı etkileyen değişiklikleri `CHANGELOG.md`'nin "Yayınlanmadı" bölümüne ekle.
7. PR şablonundaki kontrol listesini doldur.

## Kurallar

Bir silme aracı geliştiriyoruz. Bu yüzden şu kurallar pazarlık konusu değil:

- **Tek silme yolu.** Dosya kaldıran her kod `AppState.remove(_:permanently:)` üzerinden geçmeli. Doğrudan `FileManager.removeItem` / `trashItem` çağırma.
- **Varsayılan Çöp Kutusu.** Yeni bir özellik kalıcı silmeyi varsayılan yapamaz.
- **Onay.** Kullanıcı arayüzünden tetiklenen her silme, ne kadar alanın ve kaç öğenin etkileneceğini gösteren bir onaydan geçmeli.
- **Ağ yok.** Uygulamaya ağ isteği, analitik ya da üçüncü taraf bağımlılık ekleme. Böyle bir ihtiyaç varsa önce issue'da tartışalım.
- **Testler kullanıcının dosyalarına dokunmaz.** Testler yalnızca geçici klasörlerde kendi oluşturdukları dosyalarla çalışmalı. Gerçek sistemle konuşan testler bir ortam değişkeniyle açılmalı (`CLEANMAC_…_TEST=1`).

## Kod stili

- Swift API Tasarım Yönergeleri'ni izle. Mevcut kodun biçimine uy (4 boşluk girinti).
- Tanımlayıcılar İngilizce, açıklama satırları ve arayüz metinleri Türkçe.
- Arayüz metinleri kullanıcıya "sen" diye hitap eder, kısa ve teknik olmayan bir dil kullanır. Silme ile ilgili her metin sonucunu açıkça söylemeli ("Çöp Kutusu'na taşınır", "geri alınamaz").
- Ağır işleri ana aktörde yapma. `Task.detached` kullan ve iptali destekle.

## Lisans

Katkıların projeyle aynı [MIT Lisansı](LICENSE) altında yayınlanır.
