# Тесты echos

## Структура

```
echosTests/               # Unit — чистая логика, без I/O. Миллисекунды.
    MultipeerPacketTests.swift
    MessagePayloadTests.swift
    PeerTests.swift

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

## Соглашения

- Имя теста: `test_<что>_<при каких условиях>_<что ожидаем>`.
- Префикс `test_KNOWN_ISSUE_` — тест описывает **текущее** поведение, а не желаемое.
  Он зелёный и держит баг под наблюдением. Когда баг чинят: инвертировать
  ожидание → тест краснеет → править код → зелёный.
- Никаких `sleep`. Ожидание асинхронного — через `XCTestExpectation`
  и `await fulfillment(of:timeout:)`.

