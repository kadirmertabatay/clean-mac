# SSS ve Sorun Giderme

## Kurulum ve açılış

### "CleanMac açılamıyor çünkü geliştiricisi doğrulanamıyor" uyarısı

Sürümler ad-hoc imzalıdır; Apple Developer ID ile imzalanmamış ve noterize edilmemiştir. Uygulamayı açmak için:

- **macOS 14:** Finder'da uygulamaya sağ tıkla › **Aç** › **Aç**.
- **macOS 15 ve sonrası:** uygulamayı bir kez açmayı dene. Sonra **Sistem Ayarları › Gizlilik ve Güvenlik** bölümünde CleanMac için çıkan **Yine de Aç** düğmesine bas.

İkili dosyaya güvenmek istemiyorsan kaynaktan derleyebilirsin: `./build-app.sh`.

### Yeniden derledikten sonra izinler tekrar soruluyor

Ad-hoc imza her derlemede değişir ve macOS izinleri imzaya bağlar. **Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi** listesinde eski CleanMac girdisini kaldırıp yenisini ekle.

### Menü çubuğu simgesi var ama pencere yok

Menü çubuğu açıkken ana pencereyi kapatmak uygulamayı kapatmaz. Simgeye tıklayıp **CleanMac'i Aç**'ı seç ya da Dock'taki simgeye tıkla. Pencere kapanınca uygulamanın da kapanmasını istiyorsan **Ayarlar › Menü çubuğu** seçeneğini kapat.

## Tarama

### Bazı klasörler "İzin yok" görünüyor

macOS bazı konumları (Mail, Mesajlar, Safari, Çöp Kutusu, iPhone yedekleri…) yalnızca **Tam Disk Erişimi** verilmiş uygulamalara açar. CleanMac'i **Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi** listesine ekleyip uygulamayı yeniden başlat. İzin vermezsen bu konumlar "Temiz" değil "İzin yok" olarak gösterilir. Uygulama boş bir sonucu yanlışlıkla "temiz" diye raporlamaz.

### Taranan toplam, diskteki "kullanılan" alandan az

Bu normaldir. Taramanın göremediği alan şunlardan oluşabilir:

- macOS sistem birimi ve Preboot / Kurtarma birimleri,
- yerel Time Machine anlık görüntüleri,
- macOS'un "temizlenebilir" olarak tuttuğu alan,
- izin olmayan klasörler,
- sanal bellek dosyaları.

**Depolama Dökümü** ekranı bu farkı birim birim açıklar. Tam resim için kapsamı **Tüm Mac (/)** yap.

### Tüm Mac taraması harici diskimi taramıyor

Bilerek böyle. `/Volumes` atlanır ki harici diskler sayıma karışmasın ve istemeden dokunulmasın. Harici bir diski taramak için kapsamdan **Farklı Klasör…** seçip diski göster.

### Tarama yavaş

İlk tarama dosya sistemi önbelleği soğukken daha uzun sürer. Tarayıcı tüm çekirdekleri kullanır; bir SSD'de ana klasör genellikle saniyeler, tüm disk bir iki dakika içinde biter. Ağ diskleri ve çok sayıda küçük dosya içeren klasörler (ör. `node_modules`) süreyi uzatır.

### "Son kullanım" tarihi yanlış görünüyor

Tarih macOS'un tuttuğu erişim tarihinden ve Spotlight'tan gelir. Bazı uygulamalar dosyaları açmadan okuyabilir ya da Spotlight bir klasörü dizinlemiyor olabilir. Eski görünen bir dosyayı silmeden önce **Hızlı Bakış** ile kontrol et.

## Temizlik

### Yanlışlıkla bir şey sildim

Öğe Çöp Kutusu'na taşındıysa **Temizlik Geçmişi** ekranında **Geri Al**'a bas; öğe eski yerine döner. Çöp Kutusu boşaltıldıysa ya da kalıcı silme seçildiyse geri alınamaz. Bu durumda Time Machine yedeğinden geri yükleyebilirsin.

### Bazı öğeler "atlandı" diyor

Silmeden hemen önce her öğe yeniden kontrol edilir. Bir öğe şu durumlarda atlanır:

- taramadan sonra değiştirilmişse,
- artık yoksa,
- hariç tutulanlardaysa,
- tekrarlarda korunacak kopya kaybolmuşsa.

Atlanan öğelerin nedeni bildirimde yazar. Listeyi güncellemek için yeniden tara.

### Önbellekleri temizledim ama boş alan değişmedi

- Öğeler Çöp Kutusu'ndaysa alan, Çöp Kutusu boşaltılana kadar kullanılmaya devam eder.
- Açık uygulamalar önbelleklerini hemen yeniden oluşturabilir.
- macOS boş alanı (özellikle APFS anlık görüntüleri varken) birkaç dakika gecikmeyle günceller.

### Önbellekleri silmek güvenli mi?

"Güvenli" etiketli kategoriler uygulamaların gerektiğinde yeniden oluşturduğu verilerdir. Silindikten sonra ilgili uygulama ilk açılışta biraz yavaş olabilir ya da bazı içerikleri yeniden indirebilir; veri kaybı olmaz. Bir uygulamanın önbelleğine hiç dokunulmasını istemiyorsan onu **Akıllı Silme**'de koru.

### Bir klasörün asla önerilmemesini istiyorum

Listede ona sağ tıkla › **Hariç Tut**. Hariç tutulanlar hiçbir listede gösterilmez, hiçbir otomatik akışa girmez ve silme sırasında son kontrolde de atlanır.

## Gizlilik

### CleanMac internete bağlanıyor mu?

Hayır. Uygulama hiçbir ağ isteği yapmaz, analitik ya da çökme raporu göndermez. Bazı özellikler sistemdeki araçları çalıştırır (`brew`, `docker`, `xcrun simctl`, `tmutil`, `diskutil`). Bu araçların kendi davranışları kendi ayarlarına bağlıdır.

### Hangi verileri saklıyor?

Temizlik geçmişini, tarama özetlerini (klasör boyutları ve büyük dosyaların yolları) ve ayarları yalnızca senin Mac'inde saklar. Ayrıntılar ve hepsini silme komutu için bkz. [safety.md](safety.md#saklanan-veriler).

## Diğer

### Arayüz neden yalnızca Türkçe?

İlk sürüm Türkçe olarak geliştirildi. Başka dillere çeviri katkıları memnuniyetle karşılanır; bkz. [CONTRIBUTING.md](../CONTRIBUTING.md).

### Intel Mac'lerde çalışır mı?

Evet. Hazır sürümler evrensel olarak (Apple Silicon ve Intel) derlenir; kaynaktan derlendiğinde de macOS 14 çalıştıran her Mac'te çalışır.
