# echos
Let's talk, but a little quieter >_<

Структура файлов(актуальна для расширения):
```
echos/
}- Models/                 # Данные и сущности
    Message.swift          # Модель сообщения + Codable для Multipeer
    Peer.swift             # Модель пира (устройства)
    TypingEvent.swift      # Модель typing-событий
}- ViewModels/             # Бизнес-логика и состояние
    ChatViewModel.swift    # @Observable + async/await + Multipeer логика
}- Views/                  # UI-компоненты
    ChatViewController.swift   # Основной экран чата (UIKit)
    MessageCell.swift          # Кастомная ячейка для бабблов
    PeersListView.swift        # SwiftUI список устройств
}- Services/                   # todo:
    MultipeerService.swift
}- Persistence/
    echos.xcdatamodeld          # CoreData модель для хранения сообщений 
    PersistenceController.swift # Singleton для управления Core Data стеком
    MessageStore.swift          # Repository для работы с сообщениями в Core Data
}- Extensions/                 # Удобные расширения
}- Resources/                  # Ассеты, цвета, локализация
}- Utilites/                   # Вспомогательные свойства
    DeviceInfo.swift           # Место хранения информации об устройстве 
    UserSettings.swift         # Хранение имени пользователя
}- Assets.xcassets/
}- Info.plist
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
  <strong>Статус MVP:</strong> в разработке · step 7 / 25+
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
- Связь через релей, когда рядом никого нет
- Ключ устройства в Keychain (CryptoKit): на релее адресуют по отпечатку ключа, а имя — просто подпись на экране

### Планы на будущее

- End-to-end шифрование переписки
- Mesh-сеть → радиус до 500+ м через ретрансляторы
- Групповые чаты
- Карта с геофенсингом (авто-подключение в зоне)
- Анонимный режим / временные имена
- Lottie-анимации и красивые темы

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
 Подпись при подключении к релею: имя закреплено за ключом, а не за тем, кто первым им назвался
| **Nordic iOS Mesh SDK**       
 Mesh-расширение радиуса (relay nodes)
| Lottie-ios               
 Красивые анимации typing и подключения                                
| **MapKit + Core Location**   
 Оффлайн-карты и геофенсинг 
| **XCTest**                    
 Unit + UI тесты (включая async)

**Почему без Combine?**  
Combine помечен как «legacy preferred alternative» в новых промптах Xcode.

## 🗓 Дорожная карта: 

### Фаза 0 — Подготовка 

- Step 1 — Проект + @Observable ViewModel + базовая структура
- Step 2 — Базовый чат UI (UITableView + input) + withObservationTracking

### Фаза 1 — Ядро чата 

- Step 3 — Multipeer discovery (AsyncStream peers)
- Step 4 — Сессия, отправка / получение сообщений
- Step 5 — Typing индикатор (AsyncStream + таймер)
- Step 6 — SwiftUI список устройств (hybrid)
- Step 7 — Core Data (асинхронное сохранение / загрузка)
- Step 8 — CryptoKit шифрование сообщений
- Step 9 — Обработка отключений и retry
- Step 10 — Тесты (unit + ui, async)

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
   
## Сборка и релиз

Выпуск собран на fastlane, лейны лежат в `fastlane/Fastfile`. Локально хватает
`bundle install`. Локаль должна быть UTF-8 — в `project.pbxproj` есть кириллица,
и на US-ASCII fastlane падает на чтении проекта; если в шелле не прописано,
достаточно `export LANG=en_US.UTF-8`. Дальше:

```bash
bundle exec fastlane tests
```

Тесты гоняются на симуляторе; конкретное устройство не зашито, scan берёт
подходящее сам. Если нужно другое — `SIMULATOR="iPhone 17 Pro" bundle exec
fastlane tests`.

```bash
bundle exec fastlane package
```

Собирает архив в конфигурации Release и упаковывает `.ipa` в `build/`. Подписи
нет: без платного Apple Developer Program экспортировать нечего, поэтому сборка
идёт с `CODE_SIGNING_ALLOWED=NO`, а `.ipa` складывается из архива вручную. На
устройство такой файл не встанет — это артефакт, который доказывает, что проект
собирается, и который можно приложить к релизу.

Версия и номер сборки в `project.pbxproj` не пишутся. Версия берётся из тега
(`v1.2.3` → `1.2.3`), номер сборки — это число коммитов в истории. Оба значения
уходят в `xcodebuild` через `xcargs`, так что рабочая копия после сборки
остаётся чистой и релиз не требует коммита «bump version».

Лейн `notes` собирает changelog из сообщений коммитов между прошлым тегом и
`HEAD` и кладёт его в `build/notes.md`. Мерж-коммиты выбрасываются, так что
список читается.

Лейн `beta` — заливка в TestFlight. Он написан, но падает с понятной ошибкой,
пока в окружении нет ключа App Store Connect (`ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8`). Появится платный аккаунт — ключ кладётся в секреты, и лейн
начинает работать без правок.

Всё это гоняет GitHub Actions. `ci.yml` запускает тесты на каждый pull request
и на пуш в `main` и `develop`. `release.yml` срабатывает на тег `v*`: тесты,
сборка, заметки, а потом `gh release create` с приложенным `.ipa`. Его же можно
запустить руками через workflow_dispatch — тогда релиз не создаётся, но сборка
и заметки проверяются. Xcode на раннере выбирается как старший из установленных,
чтобы не переписывать путь при каждом обновлении образа.


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
