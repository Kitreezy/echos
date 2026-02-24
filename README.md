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
}- Extensions/                 # Удобные расширения
}- Resources/                  # Ассеты, цвета, локализация
}- Utilites/                   # Вспомогательные свойства
    DeviceInfo.swift           # Место хранения информации об устройстве 
    UserSettings.swift         # Хранение имени пользователя
}- Assets.xcassets/
}- Info.plist
```
# echos 

**Оффлайн-чат на iOS без интернета** — общайтесь в радиусе ~100 м через Bluetooth / Wi-Fi (P2P).  
Эхо твоих слов доходит только до тех, кто рядом.

![echos Hero](https://via.placeholder.com/1200x400/1e40af/ffffff?text=echos+-+Offline+Proximity+Chat)  
<!-- здесь будут ссылки/или изображения макетов приложения -->

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/iOS-17%2B-blue?logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Xcode-17%2B-007ACC?logo=xcode&logoColor=white" alt="Xcode 17+">
  <img src="https://img.shields.io/badge/Architecture-MVVM%20%2B%20Concurrency-green" alt="MVVM + Concurrency">
  <img src="https://img.shields.io/badge/Offline-100%25%20P2P-important" alt="Offline P2P">
</p>

<p align="center">
  <strong>Статус MVP:</strong> в разработке · step 1 / 25+
</p>

## ✨ О проекте

**echos** — это минималистичный оффлайн-мессенджер, который работает без интернета и сотовой связи.  
Идеально для фестивалей, походов, концертов, конференций, глэмпинга, протестов, яхт-клубов — везде, где нет сети.

### Основные возможности MVP

- Обнаружение устройств поблизости (~100 м)
- Приватный 1:1 чат
- Индикатор «печатает…» (typing)
- Локальная история сообщений (сохраняется даже после перезапуска)
- End-to-end шифрование сообщений (CryptoKit)

### Планы на будущее

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
 Простое и быстрое end-to-end шифрование
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
- (актуальны для расширения)
