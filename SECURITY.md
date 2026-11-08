# Güvenlik Politikası

CleanMac dosya silen bir uygulama olduğu için güvenlik hatalarını ciddiye alıyoruz. Bu kapsamda en önemli hatalar, kullanıcının onaylamadığı ya da korumaya aldığı bir şeyin silinmesine yol açanlardır.

## Desteklenen sürümler

| Sürüm | Destek |
|---|---|
| En son yayınlanan sürüm | ✅ |
| Daha eski sürümler | ❌ En son sürüme güncelle |

## Bir açığı bildirme

**Lütfen güvenlik açıklarını herkese açık issue olarak bildirme.**

GitHub'ın özel bildirim özelliğini kullan: depo sayfasında **Security › Report a vulnerability** ([doğrudan bağlantı](https://github.com/kadirmertabatay/clean-mac/security/advisories/new)).

Bildirimine şunları eklersen çok yardımcı olur:

- etkilenen sürüm ve macOS sürümü,
- sorunu yeniden oluşturma adımları (mümkünse geçici bir klasörde, sahte dosyalarla),
- beklenen ve gerçekleşen davranış,
- olası etki (ör. "hariç tutulan bir klasör Akıllı Silme planına giriyor").

## Süreç

- Bildirimin 7 gün içinde yanıtlanır.
- Sorun doğrulanırsa düzeltme önceliklendirilir ve yeni bir sürümle yayınlanır.
- İstersen sürüm notlarında adınla teşekkür edilir.

## Kapsam

Şunlar güvenlik sorunu sayılır:

- onay penceresi olmadan bir şeyin silinmesi,
- hariç tutulan ya da Akıllı Silme ile korunan bir yolun silinmesi veya bir plana girmesi,
- tekrarlarda bir dosyanın son kopyasının silinmesi,
- son an doğrulamasının (değişmiş ya da taşınmış dosya) atlatılabilmesi,
- yönetici yetkisiyle çalışan komutlara dışarıdan girdi enjekte edilebilmesi,
- uygulamanın ağ üzerinden veri göndermesine yol açan her şey.

Şunlar genellikle kapsam dışıdır:

- ad-hoc imzalı ve noterize edilmemiş sürümlerin macOS uyarıları (bilinen durum),
- kullanıcının açıkça seçtiği kalıcı silme işlemleri,
- macOS'un kendi araçlarındaki (`tmutil`, `diskutil`, `brew`, `docker`) sorunlar.
