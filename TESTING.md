# Тесты echos

## Структура

```
echosTests/               # Unit — чистая логика, без I/O. Миллисекунды.
    Support/
        LoopbackTransport.swift   # подставной PeerTransport
        SpyMessageStore.swift     # хранилище-шпион
        FakeNetworkMonitor.swift  # подставной NWPathMonitor
        RelayServer.swift         # WebSocket-сервер на NWListener
        RelayFixture.swift        # трейт .relayServer — свой релей на тест
        Tags.swift                # теги network / crypto / persistence
        AsyncTestSupport.swift    # waitUntil / firstElement / collect
    MultipeerPacketTests.swift
    MessagePayloadTests.swift
    PeerTests.swift
    RelayEnvelopeTests.swift        # конверт релея, без сети
    AsyncBroadcastTests.swift       # мультикаст поверх AsyncStream
    StreamOperatorsTests.swift      # операторы swift-async-algorithms
    ChatViewModelStreamTests.swift  # конвейер ViewModel целиком
    WebSocketClientTests.swift      # клиент против живого сервера
    WebSocketTransportTests.swift   # два «устройства» через один релей
    NetworkAwarenessTests.swift     # пропажа и возврат сети
    TransportLifecycleTests.swift   # уход в фон и возврат
    Contract/
        WebSocketContractTests.swift  # общий контракт для любого транспорта

echosIntegrationTests/    # Integration — настоящий Core Data стек в памяти.
    Support/
        CoreDataTestStack.swift
    MessageStoreIntegrationTests.swift

echosUITests/             # UI — XCUITest, приложение целиком. Десятки секунд.
    AccessibilityAuditTests.swift
```

Разделение — по **скорости и хрупкости**, а не по «типу файла».
Unit гоняются на каждое сохранение, интеграционные — перед пушем.

## Запуск

Тесты — на Swift Testing. Два тест-плана: `echos` (по умолчанию) гоняет всё,
`Fast` — всё, кроме тега `network`, то есть без настоящего сокета и релея.
Fast идёт вдвое быстрее и годится на каждое сохранение, полный — перед пушем.
Третий план, `Accessibility`, — только UI-тесты, их в первые два не включали:
они запускают приложение и идут минуты.

План `echos` собирает покрытие таргета приложения, и CI проверяет его порогом
(`scripts/coverage.py`, подробности — в README). Покрытие видно и локально:
Xcode → Report navigator → Coverage после прогона этого плана.

```bash
xcodebuild test -project echos.xcodeproj -scheme echos -testPlan Fast -destination 'platform=iOS Simulator,name=iPhone 17'
```

Полный — тот же вызов без `-testPlan` или с `-testPlan echos`. Симуляторов с
одним именем бывает несколько — тогда `-destination 'id=…'`; список —
`xcrun simctl list devices available`.

## Как устроена изоляция

- **Core Data.** Каждый тест поднимает свой `PersistenceController(inMemory: true)`.
  Это настоящий SQLite-стек (предикаты, sort descriptors, `NSBatchDeleteRequest`
  работают по-честному), но с файлом `/dev/null` — база живёт только в памяти
  процесса. `PersistenceController.shared` в тестах не используется никогда.
- **Транспорт.** `MultipeerConnectivity` требует двух реальных устройств и
  разрешения на локальную сеть, поэтому в тестах он подменяется через протокол
  `PeerTransport`. `ChatViewModel.initialize(transport:store:)` — точка внедрения.
- **Сеть.** Здесь наоборот: подмены нет. `RelayServer` поднимает настоящий
  `NWListener` с `NWProtocolWebSocket` в том же процессе, и клиент ходит на
  `ws://127.0.0.1`. Мок бесполезен — проверяется как раз то, чего он не умеет:
  разрыв TCP, переподключение, молчащий pong. Сервер можно уронить и поднять
  обратно на том же порту.
- **Состояние сети.** А вот `NWPathMonitor` подменяется: пропажу Wi-Fi на
  симуляторе не воспроизвести. `FakeNetworkMonitor` разыгрывает любой сценарий
  за миллисекунды.
- **Keychain.** Два слоя. Политика — что делать, когда устройство заперто,
  когда под ключом лежит мусор, когда запись упала на полпути — живёт в
  `IdentityStore` и проверяется юнит-тестами через `FakeSecretStore`, которому
  можно приказать сломаться. Сам `KeychainSecretStore` проверяется на настоящем
  Keychain симулятора в интеграционных тестах под одноразовым `service`: там
  важно, как отвечает Security, а не как мы это трактуем.

## Параллельный запуск

Swift Testing гоняет тесты параллельно в одном процессе — и наборы, и тесты
внутри набора. XCTest гонял класс по одному методу, и всё общее, что тесты
трогали, никому не мешало. Переход это вскрыл, и правила отсюда:

- **Ничего глобального.** Что код слушает или пишет глобально, тест получает
  своё. `WebSocketTransport` и `WallViewModel` берут центр уведомлений
  параметром: «приложение свернули» из одного теста иначе сворачивало
  транспорты всех соседних, а «изменения из iCloud» перечитывали чужую стену.
- **Общее хранилище — по очереди.** Тесты, которые пишут в один и тот же
  UserDefaults, помечены `.serialized` (черновики и шаблоны мозаики).
  Keychain и Core Data изолированы иначе: свой `service` и свой стек на тест.
- **Ждать нужную сторону.** Релей считает клиента своим раньше, чем клиент
  переводит своё состояние, а ключ собеседника приходит отдельным кругом
  после рукопожатия. Под нагрузкой эти зазоры попадали в проверки: ждите
  того, что проверяете, а не соседнего события.
- **Подготовка и уборка.** Подготовка — `init`, синхронная уборка — `deinit`
  в наборе-классе, асинхронная — трейт с областью действия, как
  `.relayServer`: асинхронного `deinit` не бывает.

Параллельный прогон нашёл и ошибку в приложении: обработчик ping вызывался
дважды при обрыве соединения, и второе возобновление продолжения роняло
процесс. У одного пользователя такое стечение редкое, у десятков соединений
в тестах — каждый раз.

## Соглашения

- Имя теста: `<что>_<при каких условиях>_<что ожидаем>`.
- Таблица входов — `@Test(arguments:)`: каждый вход — отдельный случай в
  отчёте. Пары входа и ожидания — через `zip`, иначе списки перемножаются.
- Известный дефект — `withKnownIssue`: тест зелёный, пока дефект на месте, и
  сообщает, когда его починили.
- Никаких `sleep` ради ожидания результата.
- Исключение — потоки. `debounce`, `throttle` и `chunked` по своей природе
  отдают результат «через интервал», ждать одного события бессмысленно. Для
  них есть `waitUntil` — опрос условия до таймаута. Чтобы тесты не занимали
  секунды, интервалы вынесены в свойства: у `ChatViewModel` это задержки
  typing и сброса очереди, у `WebSocketClient` — ping, таймаут pong и откат.
- У потоков состояния (`peerStream`, `stateUpdates`) первый пришедший элемент
  и ожидаемый — разные вещи: новому подписчику реплеится последнее значение.
  Берите `firstElement(of:where:)`. `collect(count: 1)` в таких местах ловит
  промежуточное состояние, и тест начинает плавать.

## Грабли с RelayServer

- `stop()` дожидается, пока listener реально отменится. `cancel()` асинхронный,
  и пока старый жив, порт занят — следующий `start()` падает с `EADDRINUSE`.
- Порт сохраняется между перезапусками, иначе клиенту некуда возвращаться.
- `received` копит всё принятое. Перед проверкой сценария с обрывом зовите
  `clearReceived()`, иначе в счёт пойдут события до обрыва.
- В `Info.plist` нужен `NSAllowsLocalNetworking`, иначе ATS режет `ws://127.0.0.1`.
  Исключение узкое, на трафик в интернет не влияет.

## Общий контракт транспорта

`WebSocketContractTests` — набор сценариев, не привязанный к конкретной
реализации `RawWebSocket`: подключение, обмен, возврат после падения сервера,
heartbeat, пауза без сети, мгновенный реконнект, доставка отложенного.
Реализации — аргументами: каждый сценарий идёт на каждой из
`RawSocketImplementation.allCases`, и в отчёте видно, на какой упало. В XCTest
это было наследованием набора, которого в Swift Testing нет.

Так сравнивался свой клиент со Starscream: `docs/adr/001-websocket-client.md`.
Ветка спайка — `spike/starscream_comparison`.

## Аудит доступности

`AccessibilityAuditTests` открывает каждый экран — главный, «Рядом», свою
стену, чат и палитру мозаики — и зовёт `performAccessibilityAudit`. Аудит
проверяет то же, что Accessibility Inspector: подписи для VoiceOver, контраст,
поддержку Dynamic Type, обрезанный текст и размер зоны нажатия. Каждый экран
проходится дважды, с обычным шрифтом и с самым крупным
(`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`):
часть проблем видна только на нём.

UI-тесты остаются на XCTest — Swift Testing приложением управлять не умеет.
Приложение запускается с аргументом `-UITests`. Тогда `PeerTransport.make()`
отдаёт `DemoTransport` с двумя засеянными собеседниками и сообщениями, а
Core Data живёт в памяти. Оба переключателя есть только в DEBUG.

Найденное аудитом в первый прогон: серый `ash` и системный `tertiaryLabel`
не дотягивали до 4.5:1, метки без `adjustsFontForContentSizeCategory` не
росли, у кнопок-иконок не было подписей, ячейка разговора на крупном шрифте
сжимала имя до одной буквы. Неочевидное — стиль `caption2` растёт на
accessibility-размерах слабее остальных, и аудит считает это частичной
поддержкой. Поэтому мелкий шрифт масштабируется по метрикам `footnote`.

Сознательное исключение одно — контраст красок палитры мозаики. ⬛ или ▪️
на тёмном фоне — это цвет рисунка, а не текст, который надо прочитать.
Исключения перечислены в `isKnownException`, новые — только с объяснением там же.

Аудит не заменяет прослушивание экрана с VoiceOver на устройстве: он проверяет,
что подпись есть, но не то, что она понятна.

```bash
xcodebuild test -project echos.xcodeproj -scheme echos -testPlan Accessibility -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Что дальше

- **Phase 3** — связка двух `ChatViewModel`. Два «устройства» в одном процессе
  уже есть: `RelayServer` плюс пара `WebSocketTransport` (см.
  `WebSocketTransportTests`). Осталось поднять проверку на уровень ViewModel —
  доставка и переходы статуса `.sending → .sent/.failed` между двумя моделями.
- **Phase 4** — сценарные XCUITest поверх той же инфраструктуры `-UITests`:
  отправка сообщения и мозаики, реакции. Плюс `addUIInterruptionMonitor` на
  системный алерт локальной сети для запуска без `DemoTransport`.
