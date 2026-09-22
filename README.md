# echos
Let's talk, but a little quieter >_<

Как устроен код:
```
echos/
  Models/          сообщение, мозаика, собеседник, росчерк, палитра эмодзи
  ViewModels/      ChatViewModel, WallViewModel — @Observable, async/await
  Views/           UIKit-экраны и SwiftUI-списки; палитра, черновик и
                   картинка мозаики, реакции, баннер о входящем
  Services/
    PeerTransport.swift      что умеет транспорт, каким бы он ни был
    MultipeerService.swift   рядом: MultipeerConnectivity
    WebSocket/               через сервер: свой WebSocket-клиент и релей
    CompositeTransport.swift оба канала разом
    Identity/                ключи устройства, рукопожатия, шифр переписки
    Network/                 есть ли сеть
  Persistence/     Core Data: два хранилища, см. ADR 002
  Utilities/       AsyncBroadcast, настройки, отсрочка в фоне
docs/adr/          почему сделано так, а не иначе
echosTests/        модульные, с поддельными транспортом и релеем
echosIntegrationTests/  с настоящими Core Data и Keychain
```
# echos 

**Чат для тех, кто рядом** — в радиусе ~100 м устройства находят друг друга сами, через Bluetooth и Wi-Fi, без интернета и сотовой связи.  
А когда рядом никого нет, разговор идёт через релей — тот же чат, только по сети.

![echos Hero](https://via.placeholder.com/1200x400/1e40af/ffffff?text=echos+-+Offline+Proximity+Chat)  
<!-- здесь будут ссылки/или изображения макетов приложения -->

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/iOS-17%2B-blue?logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Xcode-17%2B-007ACC?logo=xcode&logoColor=white" alt="Xcode 17+">
  <img src="https://img.shields.io/badge/Architecture-MVVM%20%2B%20Concurrency-green" alt="MVVM + Concurrency">
  <img src="https://img.shields.io/badge/Transport-P2P%20%2B%20Relay-important" alt="P2P + Relay">
</p>

<p align="center">
  <strong>Статус:</strong> ядро готово — фаза 1 закрыта
</p>

## ✨ О проекте

**echos** — минималистичный мессенджер, которому интернет нужен не всегда.  
Рядом — фестивали, походы, концерты, конференции, глэмпинг, яхт-клубы, где сети нет вовсе. Далеко — свой релей, если собеседник в другом городе.

### Основные возможности MVP

- Обнаружение устройств поблизости (~100 м)
- Приватный 1:1 чат
- Индикатор «печатает…» (typing)
- Локальная история сообщений (сохраняется даже после перезапуска)
- Стена: рисунок, оставленный на стене собеседника
- Мозаика: рисунок из эмодзи на сетке, который у собеседника не разъезжается. Рисуется прямо в чате, палитра вместо клавиатуры — все эмодзи, что есть в системе; начатое не пропадает
- Удачную мозаику можно сохранить и взять за основу в следующий раз, а картинкой — унести в фотоплёнку или в любой другой мессенджер
- Реакции: нажатие на сообщение — ряд эмодзи; та же ещё раз — снята
- Текст выделяется прямо в ленте, ссылки живые; неотправленное повторяется нажатием
- Входящее не в открытый чат — баннером сверху на любом экране и числом в списке разговоров. Свернули ответить и вернулись — сообщение дошло и ждёт: соединение переживает полминуты в фоне
- Рядом и через сервер разом: кто рядом — напрямую, остальные через релей, и один человек в списке один раз
- Личность — ключ устройства в Keychain: адресуют по отпечатку ключа, имя — просто подпись на экране, назваться чужим нельзя
- Переписка зашифрована между устройствами: релей её переносит, но прочитать не может; ключ свой на каждую сессию, так что записанное прошлое не открыть даже утёкшим ключом
- Свой адрес — на главном экране, адрес собеседника — под его именем в чате: сверить и заметить посредника можно глазами

### Планы на будущее

- Mesh-сеть → радиус до 500+ м через ретрансляторы
- Групповые чаты
- Карта с геофенсингом (авто-подключение в зоне)
- Анонимный режим / временные имена
- Lottie-анимации и красивые темы

Чего не будет: уведомлений на экране блокировки. Пуши шлёт сервер, а он о
содержимом не знает и знать не должен; локальные приходили бы через раз —
полминуты в фоне и тишина. Почему пробовали и отказались — [ADR 005](docs/adr/005-local-notifications.md).

## 🔒 Как это защищено

У устройства два долгих ключа в Keychain. Подписывающий — это личность: его
отпечаток служит адресом, им подтверждается право на имя при каждом
подключении, рядом и на релее одинаково. Ключ соглашения — для переписки.

На каждое подключение заводится ещё один, сессионный, подписанный личностью.
Ключ переписки выводится из двух общих секретов, сессионного и статического:
первый даёт прямую секретность, второй держит привязку к личности. Сообщение
запечатывается AES-GCM, направление конверта входит в проверяемые данные.

Релей видит адреса, чтобы доставить, и ничего больше. Подменить ключи он не
может: они подписаны, а отпечаток сверяется с адресом. Собеседник без
проверенных ключей в список не попадает.

Подробнее — [ADR 003](docs/adr/003-end-to-end-encryption.md) и
[ADR 004](docs/adr/004-session-keys.md). Стена запечатывается так же, как
сообщения. Открытым идёт только «печатает…» — запечатанное, оно выдало бы
то же самое временем.

## 🛠 Технологический стек 

| Технология              |
|-------------------------|
| **Swift 5.9+**                
 Современный, безопасный, concurrency-first
| **@Observable + async/await**  
 Реактивность и асинхронность без Combine (готов к Swift 6)
| **UIKit**   
 Полный контроль над чатом (UITableView, custom bubbles) 
| **SwiftUI**                   
 Быстрые экраны (список устройств, настройки) — hybrid подход
| **MultipeerConnectivity**     
 Нативный P2P (Bluetooth + Wi-Fi) 
| **Core Data**
 Локальное надёжное хранение сообщений                                 
| **CryptoKit**                 
 Ed25519 — личность и подписи, X25519 + HKDF + AES-GCM — шифр переписки
| **XCTest**                    
 Модульные и интеграционные тесты, async; сетевые — против настоящего релея в процессе
| *В планах:* Nordic iOS Mesh SDK, MapKit + Core Location, Lottie

**Почему без Combine?**  
Combine помечен как «legacy preferred alternative» в новых промптах Xcode.

## 🗓 Дорожная карта: 

### Фаза 0 — Подготовка 

- Step 1 — Проект + @Observable ViewModel + базовая структура
- Step 2 — Базовый чат UI (UITableView + input) + withObservationTracking

### Фаза 1 — Ядро чата — закрыта

- Step 3 — Multipeer discovery (AsyncStream peers)
- Step 4 — Сессия, отправка / получение сообщений
- Step 5 — Typing индикатор (AsyncStream + таймер)
- Step 6 — SwiftUI список устройств (hybrid)
- Step 7 — Core Data (асинхронное сохранение / загрузка)
- Step 8 — CryptoKit: личность, рукопожатия, шифрование переписки
- Step 9 — Обработка отключений и retry
- Step 10 — Тесты (unit + integration, async)

Сверх плана: связь через релей и оба канала разом.

### Фаза 2–3 — Улучшения и масштаб (следуюище шаги (step 11...25))

- Custom message bubbles & UI polish
- Nordic Mesh SDK (multi-hop)
- MapKit + геофенсинг
- Lottie анимации
- TestFlight + polish перед релизом



## 🚀 Как запустить

1. Клонируй репозиторий
   ```bash
   git clone https://github.com/Kitreezy/echos.git
   ```
   
## TODO: - для развертывания проекта



----------------------------------------------------------

## Материалы

- [Observation framework](https://developer.apple.com/documentation/observation)  
- [WWDC23: Discover Observation in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10149/)  
- [AsyncStream (Swift Evolution #0314)](https://github.com/apple/swift-evolution/blob/main/proposals/0314-async-stream.md)  
- [@MainActor](https://developer.apple.com/documentation/swift/mainactor)
- [UITableView Self-Sizing Cells](https://developer.apple.com/documentation/uikit/uitableview/rowheight)
- [UIGestureRecognizer Guide](https://developer.apple.com/documentation/uikit/touches-presses-and-gestures)
- [UITextField Return Key Types](https://developer.apple.com/documentation/uikit/uireturnkeytype/)
- [Apple Docs: MultipeerConnectivity](https://developer.apple.com/documentation/multipeerconnectivity)
- [MCNearbyServiceAdvertiser](https://developer.apple.com/documentation/multipeerconnectivity/mcnearbyserviceadvertiser)
- [MCNearbyServiceBrowser](https://developer.apple.com/documentation/multipeerconnectivity/mcnearbyservicebrowser)
- [AsyncStream Guide](https://developer.apple.com/documentation/swift/asyncstream)
- [Apple Docs: MCSession](https://developer.apple.com/documentation/multipeerconnectivity/mcsession)
- [MCSessionDelegate](https://developer.apple.com/documentation/multipeerconnectivity/mcsessiondelegate)
- [Data Reliability](https://developer.apple.com/documentation/multipeerconnectivity/mcsessionsenddatamode/)
- [UITextField Editing Events](https://developer.apple.com/documentation/uikit/uitextfield)
- [Task sleep](https://developer.apple.com/documentation/swift/task/sleep(for:tolerance:clock:))
- [Timer в Swift](https://developer.apple.com/documentation/foundation/timer)
- [UserDefaults Guide](https://developer.apple.com/documentation/foundation/userdefaults)
- [UIAlertController](https://developer.apple.com/documentation/uikit/uialertcontroller)
- [UIHostingController](https://developer.apple.com/documentation/swiftui/uihostingcontroller)
- [SwiftUI List](https://developer.apple.com/documentation/swiftui/list)
- [Core Data Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/)
- [NSPersistentContainer](https://developer.apple.com/documentation/coredata/nspersistentcontainer)
- [NSManagedObjectContext](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext)
- (актуальны для расширения)
