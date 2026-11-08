# Güvenlik ve Gizlilik

CleanMac dosya silen bir uygulama. Bu belge hangi güvencelerin nerede uygulandığını, neyin saklandığını ve bilinen sınırları anlatır. Amaç, kullanıcının ve katkıda bulunanların uygulamanın neden güvenli olduğunu kodla birlikte doğrulayabilmesi.

## İlkeler

1. **Onaysız silme yok.** Kullanıcı arayüzündeki her silme bir onay penceresinden geçer. Tek istisna, kullanıcının bir kural için açıkça "Onay istemeden uygula" seçmesidir.
2. **Geri alınabilirlik varsayılandır.** Öğeler `FileManager.trashItem` ile Çöp Kutusu'na taşınır ve Çöp Kutusu'ndaki yerleri geçmişe kaydedilir.
3. **Son anda yeniden doğrula.** Tarama ile silme arasında geçen sürede dünya değişmiş olabilir; her öğe silinmeden hemen önce yeniden kontrol edilir.
4. **Şüphede atla.** Bir kontrol belirsiz kalırsa öğe silinmez, "atlandı" olarak raporlanır.
5. **Ağ yok.** Uygulama hiçbir ağ isteği yapmaz ve hiçbir veri Mac'ten çıkmaz.

## Silme akışı

Tüm silmeler tek bir yoldan geçer: `AppState.remove(_:permanently:)` ([AppState.swift](../Sources/CleanMac/AppState.swift)).

```
Ekran (onay penceresi)
   └─► RemovalTarget listesi  (url, boyut, beklenen değiştirilme tarihi, korunacak kopyalar)
         └─► her öğe için safetyProblem(...)  ── sorun varsa ──► atlandı + nedeni
               └─► trashItem (varsayılan)  ya da  removeItem (yalnızca kalıcı seçildiyse)
                     └─► HistoryRecord (orijinal yol, Çöp Kutusu yolu, boyut, tarih)
```

`safetyProblem` silmeden hemen önce şunları kontrol eder:

| Kontrol | Neyi önler |
|---|---|
| Yol **hariç tutulanlar** listesinde ya da onun altında mı? | Kullanıcının koruduğu bir şeyin herhangi bir akıştan silinmesi |
| Öğe hâlâ var mı? (`lstat`, sembolik bağlantıyı takip etmeden) | Başka bir yere taşınmış ya da zaten silinmiş öğe için yanlış işlem |
| Değiştirilme tarihi taramadakiyle aynı mı? | Taramadan sonra üzerinde çalışılmış bir dosyanın silinmesi |
| (Tekrarlarda) korunacak kopyalardan en az biri hâlâ var mı? | Bir içeriğin **son** kopyasının silinmesi |

Akıllı Silme ve Otomatik Temizlik buna ek olarak plan hazırlanırken **Akıllı Silme korumalarını** uygular (`SmartPlanner.filter`, `AppState.isSmartProtected`).

## Kalıcı silme ne zaman yapılır?

Yalnızca şu durumlarda:

- **"Gereksiz dosyaları kalıcı sil"** ayarı açıksa. Bu ayar Ayarlar'da ve Gereksiz Dosyalar ekranının altında aynı ayardır, varsayılan olarak kapalıdır. Açıkken şu durumlarda kalıcı silme yapılır:
  - Gereksiz Dosyalar ekranından temizlenen öğeler,
  - asistanın hızlı **Temizle** düğmesi (yalnızca "güvenli" kategorilerde),
  - Akıllı Silme planındaki yeniden oluşturulabilir önbellek grupları.
- **Çöp Kutusu** kategorisi temizlenirken, çünkü Çöp Kutusu'nu boşaltmak doğası gereği kalıcıdır.

Şunlar her zaman Çöp Kutusu'na gider:
- tekrarlar,
- büyük dosyalar,
- uygulamalar ve kalıntıları,
- arşivlenen dosyaların kaynakları,
- Akıllı Silme'deki yeniden oluşturulamayan gruplar (kopyalar, proje bağımlılıkları, indirmeler).

## Tarama sırasında korumalar

- **Korumalı konumlar:** şunlar "korumalı" işaretlenir:
  - `/System`, `/usr`, `/bin`, `/sbin`, `/Library`, `/Applications`, `/opt`, `/etc`, `/private/var/db` ve `/private/var/vm`,
  - yolunda bir `Library` klasörü geçen her şey (`~/Library` dahil),
  - macOS'un paket saydığı klasörlerin içi (`.app`, `.photoslibrary` …). Bunlar büyük dosya ve tekrar listelerinde varsayılan olarak gizlenir; Akıllı Seç ve Akıllı Silme planı korumalı dosyaları seçmez.
- **Atlanan yollar:** `/Volumes` (harici diskler), `/System/Volumes` ve diski ikinci kez gösteren sanal yollar (`/.nofollow`, `/.resolve`, `/.vol`, `/dev`, `/net` …) taranmaz. Böylece hem sayımlar ikiye katlanmaz hem de harici disklere istemeden dokunulmaz.
- **Sembolik bağlantılar takip edilmez.** Boyut hesabında bağlantının kendisi sayılır.
- **iCloud:** yalnızca bulutta duran (yerel kopyası olmayan) dosyalar okunmaz, böylece özet hesaplamak indirme tetiklemez.
- **Sabit bağlantılar:** aynı inode'a işaret eden yollar tek dosya sayılır, birbirinin kopyası gibi gösterilmez.

## Akıllı Silme korumaları

Kullanıcının seçtiği her koruma (kişisel alan, tarayıcı, uygulama, geliştirici alanı) bir yol ve anahtar kelime kümesine çevrilir. Bir öğe şu durumlarda korunur:

1. öğenin yolu korumayla eşleşiyorsa,
2. öğe korunan bir yolu **içeriyorsa** (örneğin `~/Library/Caches/Google` içinde Chrome önbelleği var),
3. öğenin doğrudan bir alt öğesi korumayla eşleşiyorsa.

2. ve 3. kurallar, bir üst klasör silinerek korumanın etrafından dolaşılmasını engeller. Korumalar `UserDefaults` içinde saklanır ve Akıllı Silme, Otomatik Temizlik ve asistanın hızlı temizleme düğmelerinde ortak olarak kullanılır.

## Yönetici yetkisi

Uygulama yönetici yetkisi olmadan çalışır. Tek istisna, yerel Time Machine anlık görüntüsü silmektir (`tmutil deletelocalsnapshots`). Komut önce normal yetkiyle denenir, başarısız olursa macOS'un standart parola penceresiyle (`osascript … with administrator privileges`) yeniden çalıştırılır. Komuta yalnızca `tmutil`'in verdiği anlık görüntü tarihi eklenir.

## Harici komutlar

Bazı özellikler sistemde yüklü araçları çalıştırır. Hepsi tam yolla ve argüman listesiyle çağrılır (kabuk yorumlaması yoktur):

| Araç | Kullanım |
|---|---|
| `diskutil`, `tmutil` | APFS birimleri, anlık görüntüler |
| `brew` | `cleanup --dry-run`, `cleanup` |
| `xcrun simctl` | Kullanılmayan simülatörleri listeleme ve silme |
| `docker` | Listeleme (`--format json`), `rm`, `rmi`, `volume rm`, `builder prune`, sanal disk TRIM |

Docker silmeleri `-f` kullanmaz; kullanımdaki imajlar ve bağlı birimler Docker tarafından reddedilir, çalışan konteynerler listeye hiç alınmaz.

## Saklanan veriler

Tüm veriler yerelde, kullanıcının hesabında tutulur:

| Ne | Nerede |
|---|---|
| Temizlik geçmişi | `~/Library/Application Support/CleanMac/history.json` |
| Tarama özetleri ("Ne Büyüdü?") | `~/Library/Application Support/CleanMac/snapshots/` (kapsam başına son 12) |
| Ayarlar, hariç tutulanlar, korumalar, kurallar | `UserDefaults` (`com.kadirmertabatay.cleanmac`) |

Tarama özetleri yalnızca klasör boyutlarını ve büyük dosyaların yollarını içerir; dosya içeriği saklanmaz. Hepsini silmek için:

```bash
rm -rf ~/Library/Application\ Support/CleanMac
defaults delete com.kadirmertabatay.cleanmac
```

## Bilinen sınırlar

- Uygulama **sandbox'lı değildir**: diski analiz edebilmek için kullanıcının erişebildiği her yere erişir. macOS'un TCC izinleri (Masaüstü, Belgeler, Tam Disk Erişimi) yine geçerlidir.
- İmza ad-hoc'tur ve uygulama noterize edilmemiştir. Kaynaktan derlemek, ikili dosyaya güvenmek zorunda kalmamanın en kesin yoludur.
- "Son kullanım" tarihleri macOS'un tuttuğu erişim tarihlerine ve Spotlight'a dayanır. Bu tarihler her zaman güvenilir değildir; eski görünen bir dosyayı silmeden önce gözden geçir.
- Kalıcı silinen öğeler geri alınamaz.

Bir güvenlik sorunu bulduysan lütfen [SECURITY.md](../SECURITY.md) adımlarını izle.
