# Тесты echos

## Структура

```
echosTests/               # Unit — чистая логика, без I/O. Миллисекунды.
    Support/
        LoopbackTransport.swift   # подставной PeerTransport
        SpyMessageStore.swift     # хранилище-шпион
        FakeNetworkMonitor.swift  # подставной NWPathMonitor
        RelayServer.swift         # WebSocket-сервер на NWListener
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
```

Разделение — по **скорости и хрупкости**, а не по «типу файла».
Unit гоняются на каждое сохранение, интеграционные — перед пушем.

## Запуск

Всё сразу (схема `echos` собирает приложение и гоняет оба бандла):

```bash
xcodebuild test -project echos.xcodeproj -scheme echos -destination 'platform=iOS Simulator,name=iPhone 16 Pro Test'
```

Только быстрые:

```bash
xcodebuild test -project echos.xcodeproj -scheme echosTests -destination 'platform=iOS Simulator,name=iPhone 16 Pro Test'
```

Список доступных симуляторов: `xcrun simctl list devices available`.

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

## Соглашения

- Имя теста: `test_<что>_<при каких условиях>_<что ожидаем>`.
- Префикс `test_KNOWN_ISSUE_` — тест описывает **текущее** поведение, а не желаемое.
  Он зелёный и держит баг под наблюдением. Когда баг чинят: инвертировать
  ожидание → тест краснеет → править код → зелёный.
- Никаких `sleep`. Ожидание асинхронного — через `XCTestExpectation`
  и `await fulfillment(of:timeout:)`.
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
Наследник подменяет `makeRawSocket(url:)` — код тестов не меняется.

Так сравнивался свой клиент со Starscream: `docs/adr/001-websocket-client.md`.
Ветка спайка — `spike/starscream_comparison`.

## Зафиксированные дефекты

| Тест | Суть |
|---|---|
| `test_KNOWN_ISSUE_loadMessagesWithPeer_leaksAllOutgoingMessages` | Предикат `isFromMe == YES OR senderName == peer`, а у исходящих `senderName == nil` → в чат с одним собеседником протекают свои реплики из других чатов. Чинится привязкой исходящих к получателю. |
| `test_KNOWN_ISSUE_deleteConversation_leavesOutgoingMessagesBehind` | Удаление диалога чистит только входящие; свои реплики остаются в базе навсегда. |

## Что дальше

- **Phase 3** — связка двух `ChatViewModel`. Два «устройства» в одном процессе
  уже есть: `RelayServer` плюс пара `WebSocketTransport` (см.
  `WebSocketTransportTests`). Осталось поднять проверку на уровень ViewModel —
  доставка и переходы статуса `.sending → .sent/.failed` между двумя моделями.
- **Phase 4** — XCUITest. Запуск приложения с launch-аргументом `-UITests`,
  который подсовывает in-memory стор и фейковый транспорт с засеянными пирами;
  плюс `addUIInterruptionMonitor` на системный алерт локальной сети.
