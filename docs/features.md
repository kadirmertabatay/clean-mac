# Özellikler

CleanMac'in kenar çubuğu üç bölümden oluşur: **Asistan** (ne yapmalıyım?), **Araçlar** (ayrıntıya in) ve **Güvenlik** (geri al, koru). Bu sayfa her ekranı sırayla anlatır.

> Ekran görüntüleri `scripts/screenshots.sh` ile sahte bir demo ana klasöründen üretilmiştir.

- [Karşılama ekranı](#karşılama-ekranı)
- Asistan: [Akıllı Asistan](#akıllı-asistan) · [Akıllı Silme](#akıllı-silme) · [Genel Bakış](#genel-bakış) · [Depolama Dökümü](#depolama-dökümü) · [Ne Büyüdü?](#ne-büyüdü)
- Araçlar: [Klasör Gezgini](#klasör-gezgini) · [Büyük Dosyalar](#büyük-dosyalar) · [Tekrarlanan Dosyalar](#tekrarlanan-dosyalar) · [Benzer Fotoğraflar](#benzer-fotoğraflar) · [Gereksiz Dosyalar](#gereksiz-dosyalar) · [Uygulamalar](#uygulamalar) · [Geliştirici](#geliştirici) · [Docker](#docker) · [Otomatik Temizlik](#otomatik-temizlik)
- Güvenlik: [Temizlik Geçmişi](#temizlik-geçmişi) · [Hariç Tutulanlar](#hariç-tutulanlar)
- [Menü çubuğu ve Ayarlar](#menü-çubuğu-ve-ayarlar) · [Tarama kapsamı](#tarama-kapsamı) · [Klavye kısayolları](#klavye-kısayolları)

---

## Karşılama ekranı

<img src="images/splash.png" width="760" alt="Karşılama ekranı">

Uygulama açılırken bir kez gösterilir: logo, tarama halkası ve diskin anlık boş alanı. Tıklayınca hemen kapanır. **Ayarlar › Görünüm** bölümünden kapatılabilir. macOS'ta "Hareketi azalt" açıksa animasyonsuz gösterilir.

## Akıllı Asistan

<img src="images/assistant.png" width="760" alt="Akıllı Asistan">

Başlangıç ekranı. **Tam Analizi Başlat** sırasıyla şunları yapar:

1. gereksiz dosya kategorilerini tarar,
2. seçilen kapsamdaki klasör ağacını çıkarır,
3. tekrarlanan dosyaları karşılaştırır,
4. depolama dökümünü ve uygulama listesini hesaplar.

Üstteki üç kart **güvenle temizlenebilir** alanı (önbellekler, günlükler, geliştirici artıkları), **gözden geçirilebilir** alanı (indirmeler, bağımlılıklar, tekrarlar) ve anlık boş alanı gösterir.

Öneriler öncelik sırasıyla listelenir: disk doluluğu uyarısı, uzun süredir kullanılmayan büyük dosyalar, tekrarlar, proje bağımlılıkları, önbellekler… Her öneride ya ilgili ekrana götüren bir düğme ya da (yalnızca "güvenli" etiketli kategorilerde) doğrudan **Temizle** düğmesi bulunur. Taramanın göremediği alan (izin olmayan klasörler, Time Machine anlık görüntüleri, macOS'un boşaltabileceği alan) ayrıca açıklanır.

## Akıllı Silme

<img src="images/smart-cleanup.png" width="760" alt="Akıllı Silme">

Tek bir temizlik planı hazırlar. Üç adımdan oluşur.

**1. Nelere dokunulmasın?** Çiplere tıklayarak kilitle:

| Grup | Örnekler | Varsayılan |
|---|---|---|
| Kişisel alanlar | Masaüstü, Belgeler, Fotoğraflar ve Videolar, Müzik, iCloud Drive, İndirilenler | İndirilenler dışındakiler korunur |
| Tarayıcılar | Chrome, Safari, Firefox, Brave, Arc, Edge… (yüklü olanlar) | Korunmaz |
| Uygulamalar | Yüklü tüm uygulamalar, aranabilir | Korunmaz |
| Geliştirici | Proje bağımlılıkları, paket önbellekleri, Xcode ve simülatörler, `~/.cache` | Korunmaz |

Bir uygulama korunduğunda, ona ait önbellekler ve veriler paket kimliği, bilinen klasör adları ve üretici klasörleri üzerinden eşleştirilir. Örneğin Chrome için `~/Library/Caches/Google/Chrome` korunur. Korunan bir şeyi **içeren** klasörler de korunur; böylece üst klasör silinerek korumanın etrafından dolaşılmaz.

**2. Ne kadar kapsamlı?**

| Düzey | Plana girenler |
|---|---|
| **Güvenli** | Uygulama önbellekleri, günlükler, Xcode DerivedData, cihaz destek dosyaları, simülatör ve paket yöneticisi önbellekleri |
| **Dengeli** | Güvenli + İndirilenler'deki kurulum dosyaları + 90 günden uzun süredir dokunulmamış projelerin bağımlılıkları + birebir aynı kopyalar (her grupta en eskisi korunur) |
| **Kapsamlı** | Dengeli + eski indirmeler + `~/.cache` + 30 günden uzun süredir dokunulmamış projelerin bağımlılıkları |

**3. Plan.** Gruplar halinde önizleme gösterilir. İstemediğin öğenin işaretini kaldırabilir ya da sağ tıklayıp **Hariç Tut** diyebilirsin. "Korunduğu için atlananlar" bölümü hangi korumanın kaç öğeyi ve ne kadar alanı kurtardığını gösterir. Onaylanınca her şey Çöp Kutusu'na taşınır. Yalnızca "Gereksiz dosyaları kalıcı sil" ayarı açıksa yeniden oluşturulabilir önbellekler kalıcı silinir.

Korumalar **Otomatik Temizlik** kurallarında ve asistanın hızlı **Temizle** düğmelerinde de geçerlidir.

## Genel Bakış

<img src="images/overview.png" width="760" alt="Genel Bakış">

Disk doluluğu, dört özet kart (gereksiz dosyalar, büyük dosyalar, tekrarlar, proje bağımlılıkları) ve taranan klasördeki en büyük öğeler.

## Depolama Dökümü

<img src="images/storage.png" width="760" alt="Depolama Dökümü">

Başlangıç diskini APFS birimlerine göre böler: Veri, macOS Sistemi, Preboot, Kurtarma, Güncelleme, Sanal Bellek. macOS'un ihtiyaç halinde kendisinin boşaltabileceği **temizlenebilir** alanı ve yerel **Time Machine anlık görüntülerini** gösterir. Anlık görüntüler buradan silinebilir; bu işlem yönetici parolası ister. Kapsam *Tüm Mac* iken taramanın göremediği alan da hesaplanır.

## Ne Büyüdü?

<img src="images/growth.png" width="760" alt="Ne Büyüdü?">

Her tarama bittiğinde klasör ağacının özeti saklanır (kapsam başına son 12 tarama). Bu ekran şimdiki taramayı seçtiğin önceki bir taramayla karşılaştırır:

- toplam değişim,
- en çok büyüyen ve küçülen klasörler (10 MB üstü, 3 seviye derinliğe kadar),
- yeni ve kaybolan büyük dosyalar (100 MB üstü).

## Klasör Gezgini

| Liste ve halka grafik | Treemap |
|---|---|
| <img src="images/explorer.png" alt="Klasör Gezgini liste"> | <img src="images/treemap.png" alt="Klasör Gezgini treemap"> |

Seçilen klasörün boyut ağacı. Çift tıklayarak içine girilir, üstteki yol çubuğuyla geri dönülür. Sağ tık menüsünde **Finder'da Göster**, **Hızlı Bakış**, **Hariç Tut** ve **Çöp Kutusu'na Taşı** bulunur. Sağ üstteki düğmelerle liste ve treemap görünümü arasında geçilir.

## Büyük Dosyalar

<img src="images/large-files.png" width="760" alt="Büyük Dosyalar">

Taramada bulunan büyük dosyaların tablosu. Ad, boyut, tür, son kullanım ve konuma göre sıralanabilir.

- Filtreler: en küçük boyut, tür (video, ses, görüntü, arşiv, disk imajı, belge…), "6+ ay kullanılmayan", arama.
- **Sistem dosyaları** seçeneği korumalı konumlardaki dosyaları da gösterir (varsayılan olarak gizli).
- Boşluk tuşu dosyayı **Hızlı Bakış** ile önizler.
- Sağ tık › **Harici Diske Arşivle**: dosyalar seçilen diske kopyalanır, kopya SHA-256 ile doğrulanır, ancak ondan sonra kaynak Çöp Kutusu'na taşınır. Klasör yapısı `CleanMac Arşivi/` altında korunur.

## Tekrarlanan Dosyalar

<img src="images/duplicates.png" width="760" alt="Tekrarlanan Dosyalar">

İçeriği birebir aynı dosyaları üç aşamada bulur: aynı boyut → baş ve son 64 KB'nin özeti → tam SHA-256. Sabit bağlantılar (aynı inode) kopya sayılmaz. Yalnızca bulutta duran iCloud dosyaları okunmaz.

- **Akıllı Seç** her gruptan en eski kopya dışındakileri seçer.
- Bir gruptaki tüm kopyaları seçmek engellenir. Silme anında korunan kopyanın hâlâ diskte olduğu yeniden kontrol edilir.
- **En az** menüsüyle küçük dosyalar elenebilir (varsayılan 1 MB).

## Benzer Fotoğraflar

<img src="images/similar-photos.png" width="760" alt="Benzer Fotoğraflar">

Seri çekimleri, yeniden boyutlandırılmış ya da yeniden kaydedilmiş kopyaları bulur. Apple Vision'ın görüntü parmak izi (`VNGenerateImageFeaturePrintRequest`) tamamen cihaz üzerinde hesaplanır ve birbirine yeterince yakın fotoğraflar gruplanır. JPEG, PNG, HEIC, TIFF, WebP ve yaygın RAW biçimleri desteklenir. **Akıllı Seç** her grupta en büyük (genellikle en kaliteli) dosyayı korur.

## Gereksiz Dosyalar

<img src="images/junk.png" width="760" alt="Gereksiz Dosyalar">

| Kategori | Etiket |
|---|---|
| Uygulama önbellekleri, günlükler | Güvenli |
| Xcode DerivedData, cihaz destek dosyaları, simülatör önbellekleri | Güvenli |
| Paket yöneticisi önbellekleri (npm, pnpm, Gradle, Cargo, Bun, Go…) | Güvenli |
| Çöp Kutusu | Güvenli (boşaltmak kalıcıdır) |
| `~/.cache` | Gözden geçir |
| İndirilenler'deki kurulum dosyaları (`.dmg`, `.pkg`, `.xip`, `.iso`) | Gözden geçir |
| Eski indirmeler (90 günden uzun süredir açılmamış) | Gözden geçir |
| Xcode arşivleri, iPhone / iPad yedekleri | Gözden geçir |
| Proje bağımlılıkları (`node_modules`, `.venv`, `Pods`…) | Gözden geçir |

"Güvenli" kategoriler uygulamaların gerektiğinde yeniden oluşturduğu verilerdir. Her kategori açılarak öğe öğe seçilebilir. **Kalıcı olarak sil** seçeneği Çöp Kutusu'nu atlar.

## Uygulamalar

<img src="images/apps.png" width="760" alt="Uygulamalar">

`/Applications` ve `~/Applications` içindeki uygulamaları boyut ve son açılma tarihiyle listeler. **6+ ay açılmayanlar** filtresi unutulan uygulamaları bulur. Bir uygulama seçildiğinde `~/Library` içinde bıraktığı dosyalar (önbellek, tercih, Application Support, kapsayıcılar…) paket kimliğiyle eşleştirilerek gösterilir. Uygulama, seçtiğin kalıntılarla birlikte Çöp Kutusu'na taşınır. Apple uygulamaları kaldırılamaz.

## Geliştirici

Geliştirici araçlarının kendi temizlik komutlarını kullanır ve önce ne silineceğini gösterir:

- **Homebrew:** `brew cleanup --dry-run` çıktısı ve tek tıkla `brew cleanup`.
- **Xcode simülatörleri:** yüklü olmayan iOS sürümlerine ait kullanılmayan simülatörler (`simctl delete unavailable`).
- **Dokunulmamış projeler:** son değişikliği seçilen süreden eski projelerin `node_modules` / `.venv` / `Pods` klasörleri.
- **Docker özeti:** `docker system df` ve `docker system prune`.

## Docker

Docker yüklüyse kenar çubuğunda görünür. Docker Desktop çalışmıyorsa tek tıkla başlatılabilir.

- **İmajlar:** etiketsiz (dangling), hiçbir konteynerin kullanmadığı, aynı imaja ait fazladan etiketler ve aynı deponun eski sürümleri ayrı ayrı işaretlenir.
- **Konteynerler:** durmuş konteynerler ve boyutları.
- **Birimler:** hiçbir konteynere bağlı olmayan (sahipsiz) birimler.
- **Derleme önbelleği:** geri kazanılabilir alan.
- **Sanal diski küçült:** Docker'ın sanal diskinde boş kalan bloklar TRIM ile macOS'a geri verilir.

Silme işlemleri Docker CLI üzerinden yapılır. Kullanılan imajlar, çalışan konteynerler ve bağlı birimler silinmez.

## Otomatik Temizlik

<img src="images/rules.png" width="760" alt="Otomatik Temizlik">

Zamanlanmış kurallar: "Her hafta uygulama önbellekleri", "Her ay paket yöneticisi önbellekleri", "30 günden eski kurulum dosyaları" gibi. Zamanı gelen bir kural:

- varsayılan olarak yalnızca **önizleme** hazırlar ve bildirim gönderir; uygulamak için onayın gerekir,
- **Onay istemeden uygula** açıksa kendiliğinden çalışır.

Her iki durumda da hariç tutulanlar ve Akıllı Silme korumaları uygulanır. Kurallar uygulama açıkken (menü çubuğunda çalışırken dahil) kontrol edilir.

## Temizlik Geçmişi

CleanMac ile kaldırılan her öğenin kaydı: orijinal yol, boyut, tarih ve Çöp Kutusu'ndaki yeri. Çöp Kutusu'nda duran öğeler **Geri Al** ile eski yerine taşınır. Eski yerde aynı adla yeni bir dosya varsa üzerine yazılmaz.

## Hariç Tutulanlar

Buraya eklenen klasör ve dosyalar hiçbir listede gösterilmez, hiçbir öneriye girmez ve silme sırasında son kontrolde de atlanır. Listelerde sağ tık › **Hariç Tut** ile eklenir, bu ekrandan kaldırılır.

## Menü çubuğu ve Ayarlar

Menü çubuğu simgesi boş alanı gösterir. Açılan pencereden analiz başlatılabilir ve ana pencere açılabilir. Menü çubuğu açıkken ana pencere kapatılsa da uygulama çalışmaya devam eder.

**Ayarlar (⌘,)**

| Ayar | Varsayılan |
|---|---|
| Açılışta karşılama ekranını göster | Açık |
| Menü çubuğunda boş alanı göster | Açık |
| Boş alan azalınca bildirim gönder (eşik %5–25) | Açık, %10 |
| Gereksiz dosyaları kalıcı sil (Çöp Kutusu'nu atla) | Kapalı |

Boş alan 5 dakikada bir kontrol edilir; günde en fazla bir bildirim gönderilir.

## Tarama kapsamı

Asistan ya da Klasör Gezgini'ndeki **Kapsam** menüsünden seçilir ve hatırlanır:

- **Ana Klasör (~):** yalnızca kullanıcı dosyaların. En hızlı seçenek.
- **Tüm Mac (/):** başlangıç diskinin tamamı. Harici diskler (`/Volumes`), `/System/Volumes` ve diski ikinci kez gösteren sanal yollar (`/.nofollow`, `/.resolve`, `/.vol`) atlanır.
- **Farklı Klasör…:** herhangi bir klasör ya da harici disk.

## Klavye kısayolları

| Kısayol | İşlem |
|---|---|
| ⇧⌘R | Tam analizi başlat |
| ⌘O | Klasör seç ve tara |
| ⌘. | Taramayı durdur |
| ⌘, | Ayarlar |
| Boşluk | Seçili dosyayı Hızlı Bakış ile önizle (listelerde) |
