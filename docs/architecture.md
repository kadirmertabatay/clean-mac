# Mimari

CleanMac, harici bağımlılığı olmayan tek bir Swift Package Manager hedefidir (`executableTarget`). Arayüz SwiftUI ile yazılmıştır. AppKit yalnızca SwiftUI'nin sunmadığı yerlerde kullanılır: Finder ile etkileşim, Çöp Kutusu, pencere yönetimi.

## Genel görünüm

```
┌──────────────────────────── SwiftUI görünümleri ────────────────────────────┐
│ AssistantView  SmartCleanView  ExplorerView  DuplicatesView  JunkView  …    │
└───────────────▲──────────────────────────────────────────┬──────────────────┘
                │ @Published durum                         │ kullanıcı eylemi
┌───────────────┴──────────────────────────────────────────▼──────────────────┐
│ AppState  (@MainActor ObservableObject, tek doğruluk kaynağı)               │
│  tarama · tekrarlar · gereksizler · akıllı plan · kurallar · güvenli silme  │
└──────┬─────────────┬──────────────┬──────────────┬──────────────┬───────────┘
       │ Task.detached (arka plan, iptal edilebilir)               │
┌──────▼─────┐ ┌─────▼────────┐ ┌───▼──────────┐ ┌─▼────────────┐ ┌▼──────────┐
│ DiskScanner│ │DuplicateFinder│ │ JunkScanner │ │ SmartPlanner │ │ Shell     │
│ (paralel)  │ │ SimilarPhotos │ │ AppInventory│ │ RuleEngine   │ │ brew/tmutil│
└────────────┘ └───────────────┘ └─────────────┘ └──────────────┘ │ docker…   │
                                                                   └───────────┘
```

- **Görünümler** durumu okur ve `AppState` üzerindeki yöntemleri çağırır. Dosya sistemine doğrudan dokunmazlar.
- **`AppState`** ana iş parçacığında yaşar. Ağır işleri `Task.detached` ile arka plana gönderir ve sonuçları `@Published` özelliklere yazar.
- **Motorlar** (`DiskScanner`, `DuplicateFinder`, `JunkScanner` …) saf, durumsuz türlerdir. Girdi alıp değer döndürdükleri için doğrudan test edilebilirler.

## Dosyalar

| Dosya | Sorumluluk |
|---|---|
| `CleanMacApp.swift` | Uygulama girişi, pencere ve menü çubuğu sahneleri, kenar çubuğu, menü komutları |
| `AppState.swift` | Merkezi durum ve tüm iş akışları; tek silme yolu `remove(_:permanently:)` ve `safetyProblem` |
| `Models.swift` | `Paths`, `FileNode`, `FileEntry`, `RemovalTarget`, `DiskInfo`, biçimlendirme yardımcıları |
| `Scanner.swift` | İş kuyruklu paralel klasör tarayıcı, korumalı yol kuralları |
| `DuplicateFinder.swift` | Boyut → kısmi özet → SHA-256 tekrar bulma |
| `SimilarPhotos.swift` | Vision görüntü parmak iziyle benzer fotoğraf gruplama |
| `JunkScanner.swift` | Gereksiz dosya kategorilerinin tanımları ve taranması |
| `SmartCleanup.swift` | Koruma kataloğu, eşleştirme kuralları, Akıllı Silme düzeyleri ve planlayıcı |
| `Rules.swift` | Otomatik temizlik kuralları ve `RuleEngine` |
| `Growth.swift` | Tarama özetleri (`SnapshotStore`) ve karşılaştırma |
| `Archive.swift` | Harici diske kopyala → doğrula → Çöp Kutusu'na taşı |
| `AppInventory.swift` | Yüklü uygulamalar ve `~/Library` kalıntıları |
| `StorageBreakdown.swift` | `Shell` yardımcısı, APFS birimleri, Time Machine anlık görüntüleri |
| `DevTools.swift`, `DockerService.swift` | Homebrew, simülatörler, Docker CLI entegrasyonu |
| `Assistant.swift` | Kural tabanlı öneri motoru ve asistan ekranı |
| `Monitor.swift` | Tercihler, boş alan izleyici, bildirimler, menü çubuğu, Ayarlar |
| `ScreenshotMode.swift` | Belgelerdeki ekran görüntülerini üreten otomatik mod (yalnızca ortam değişkeniyle açılır) |
| `*View.swift`, `Components.swift`, `TreemapView.swift`, `SplashView.swift` | Ekranlar ve paylaşılan bileşenler |

## Tarayıcı

`DiskScanner` büyük ağaçları (ör. tüm disk, milyonlarca dosya) hızlı ve tutarlı taramak için tasarlandı.

1. **İş kuyruğu.** Kök klasör bir `JobQueue`'ya konur. Çekirdek sayısı kadar işçi (`DispatchQueue.concurrentPerform`) kuyruktan iş çeker.
2. **Sığ bölme, derin özyineleme.** İlk 4 seviyedeki (`splitDepth`) klasörlerin yalnızca kendi içeriği okunur ve alt klasörleri yeni iş olarak kuyruğa eklenir. Daha derin klasörler tek iş içinde özyinelemeli taranır. Böylece tek bir dev klasör (ör. `~/Library`) taramayı tek çekirdeğe mahkûm etmez, iş sayısı da kontrolsüz büyümez.
3. **Aşağıdan yukarı toplama.** İşçiler bitince bölünen klasörler derinden köke doğru sıralanır ve boyutlar üst klasörlere eklenir. Bu aşama kilitsiz ve tek iş parçacıklıdır.
4. **Boyut ölçümü.** Dosya boyutu olarak diskte gerçekten kaplanan alan kullanılır (`totalFileAllocatedSize`). Seyrek dosyalar ve sıkıştırılmış dosyalar Finder'daki gibi sayılır.
5. **Takip edilen dosyalar.** 1 MB üstü dosyalar büyük dosya, tekrar ve benzer fotoğraf analizleri için ayrıca listelenir. `node_modules`, `.venv`, `Pods` gibi klasörler "geliştirici artığı" olarak işaretlenir.
6. **İptal ve ilerleme.** `ScanCoordinator` iptal bayrağını ve kısıtlanmış (throttled) ilerleme bildirimlerini yönetir.

Hariç tutulan sanal yollar, korumalı kökler ve paket algılaması için bkz. [safety.md](safety.md#tarama-sırasında-korumalar).

## Tekrar bulma

```
tüm takip edilen dosyalar
  └─ boyuta göre grupla (tekil boyutlar elenir, sabit bağlantılar tekilleştirilir)
       └─ baş + son 64 KB özeti (çoğu aday burada elenir)
            └─ tam SHA-256 (yalnızca kalanlar için)
```

Yalnızca bulutta duran iCloud dosyaları okunmaz (`SF_DATALESS` / ayrılmış blok yok). Gruplar boşa giden alana göre sıralanır.

## Eşzamanlılık modeli

- Paket Swift 5 dil modunda derlenir; `AppState` ve görünümler `@MainActor`'dır.
- Uzun işler `Task.detached` ile başlatılır, görev referansı saklanır ve `cancelScan()` hepsini iptal eder.
- Motorlar arka planda çalışır ve ana aktöre yalnızca değer (struct, sınıf ağacının sahipliği) döndürür. İlerleme geri çağrıları `Task { @MainActor in … }` ile aktarılır.
- Silme işlemi de arka planda yapılır. Geçmiş ve listeler sonuç geldikten sonra ana aktörde güncellenir.

## Kalıcılık

| Veri | Mekanizma |
|---|---|
| Ayarlar, hariç tutulanlar, korumalar, kurallar, tarama kapsamı | `UserDefaults` (`Prefs`, `@AppStorage`) |
| Temizlik geçmişi | JSON, `Paths.dataDirectory/history.json` |
| Tarama özetleri | JSON, `Paths.dataDirectory/snapshots/<kök yolun SHA-256 öneki>.json` |

`Paths.home` ve `Paths.dataDirectory` ortam değişkenleriyle değiştirilebilir. Testler ve ekran görüntüsü üretimi bunu kullanır (bkz. [development.md](development.md#ortam-değişkenleri)).

## Testler

`Tests/CleanMacTests` altındaki testler geçici klasörlerde gerçek dosyalar oluşturarak şunları doğrular:
- tarayıcı,
- tekrar bulucu,
- güvenli silme kontrolleri,
- geri alma,
- Akıllı Silme eşleştirmeleri,
- kurallar,
- arşivleme,
- Docker çıktı ayrıştırma,
- benzer fotoğraflar,
- karşılama ekranının çizimi.

Testler kullanıcının dosyalarına dokunmaz. Gerçek sistemle konuşan testler (Docker, hız ölçümü) ortam değişkeniyle açılır.

## Tasarım kararları

- **Bağımlılık yok.** Bir silme aracının tedarik zinciri saldırı yüzeyi olabildiğince küçük olmalı. Her şey Apple çerçeveleriyle yapılır.
- **Sandbox yok.** Disk analizi için gerekli. Bunun yerine güvenlik silme yolunun tekliği, son an doğrulaması ve Çöp Kutusu varsayılanıyla sağlanır.
- **Tek silme yolu.** Hangi ekrandan gelirse gelsin, her silme `AppState.remove` ve `safetyProblem` üzerinden geçer. Yeni bir özellik eklerken bu yolu kullanmak zorunludur.
- **Önce anlat, sonra sil.** Her kategori ve öneri, silinirse ne olacağını açıklayan bir metin taşır.
