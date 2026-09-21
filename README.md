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

## Кэш в CI

Прогон на macOS-раннере тратит время на три вещи, которые от коммита к
коммиту не меняются: гемы fastlane, пакеты SPM и компиляцию того, что уже
компилировалось в прошлый раз. Всё три кэшируются; первое делает
`ruby/setup-ruby` с `bundler-cache`, остальное — composite action
`.github/actions/xcode-cache`, один на оба workflow.

Чтобы кэшировать, нужно знать, где искать. По умолчанию xcodebuild кладёт и
пакеты, и DerivedData в `~/Library/Developer/Xcode/DerivedData` в папку с
хэшем в имени, и этот хэш от машины к машине разный. Поэтому в Fastfile оба
пути заданы явно: `build/SourcePackages` и `build/DerivedData`. Локально это
ничего не меняет, кроме того, что `rm -rf build` теперь сбрасывает и их.

Пакеты привязаны к `Package.resolved`: пока зависимости не менялись, ключ тот
же и клонировать с GitHub нечего. С DerivedData хитрее. Точный ключ считается
от исходников и почти никогда не совпадает — любой коммит его меняет. Смысл
в `restore-keys`: если точного нет, берётся последний слепок для этой версии
Xcode, и сборка становится инкрементальной — xcodebuild пересобирает только
файлы, которые изменились с того слепка. Версия Xcode в ключе обязательна:
продукты разных версий несовместимы, и старый слепок не ускорит, а
испортит сборку. После прогона `actions/cache` сохраняет новый слепок под
точным ключом, так что следующий коммит откатится уже на него.

На странице прогона в Summary — таблица: попали ли пакеты в кэш, какой слепок
DerivedData восстановлен и сколько секунд шли тесты. По ней и сравнивать.
Первый прогон после этого изменения холодный по определению, кэша ещё нет;
смотреть надо на второй и дальше.

Что это даёт, видно и без раннера. На маке с M-серией `fastlane tests` с
пустым `build/` занял 72 секунды, из них 17 на компиляцию; с тёплыми
DerivedData и пакетами — 52 секунды и 6 на компиляцию, остальное симулятор и
сами тесты, которые кэш не трогает. DerivedData при этом весит 219 МБ, пакеты
40 — это то, что раннер будет скачивать из кэша вместо того, чтобы собирать.
На раннере GitHub процессор медленнее, а пакеты идут по сети, так что разница
там больше, чем в этих цифрах.

## Цикл проверки

Сборка и тесты детерминированы, их делает `xcodebuild`. Третий шаг —
прочитать, что упало, и понять, почему, — до сих пор был ручным.
`scripts/check.sh` замыкает цикл: собирает, гоняет тесты, вытаскивает
падения из `.xcresult` через `scripts/failures.py` в читаемом виде — имя
теста, сообщение, строка, а не лог на сорок тысяч строк — и отдаёт их
`claude -p`. Зелёный прогон до модели не доходит вовсе. Если упал сам
хост-процесс, в `.xcresult` пусто, и скрипт добавляет пути к свежим
крэш-репортам — модель прочитает их сама.

Без флагов модель только объясняет: что сломано, где и что стоит сделать.
С `--fix` ей разрешено править, и после правки тесты идут снова — до трёх
кругов. Три, а не бесконечность: если за три попытки не починилось, чинить
надо человеку, и скрипт обязан это сказать, а не крутиться. Запускать
перед PR или из pre-push; нужен Claude Code в PATH и вход в аккаунт.

Проверялось на настоящем падении. Сломанный отпечаток ключа — 7 байт вместо
8 — уронил десять тестов каскадом: транспорт перестал узнавать себя в
присутствии, сообщения перестали доходить. Первый круг вернул `prefix(8)`
и объяснил каскад, тесты не тронул — «16 символов это условие
совместимости с релеем, а не просто ожидание в ассерте». Второй круг упал
на другом: `makePair()` в тестах ждал двух принятых соединений, а не двух
представившихся, и сообщение, отправленное в зазор между ними, релей
выбрасывал. Это была настоящая гонка в тестовой обвязке, не связанная с
поломкой, — она всплывала и до неё, только реже. Второй круг завёл
`introducedClientCount` и дождался его. Третий круг зелёный. То же место
есть в `WebSocketContractTests` — там пока не поправлено.

В CI — второй job `review` в `ci.yml`, после тестов, только на pull
request. Модель не собирает и не тестирует, это уже сделано; она читает
diff и `build/failures.txt` из артефакта и оставляет в PR один
комментарий: если упало — что и где, если прошло — что в diff тесты не
поймают. Ходит по подписке через `CLAUDE_CODE_OAUTH_TOKEN` из
`claude setup-token`; без секрета job пропускается.

Что стоит записывать, пока это обучение: сколько кругов уходит на типовое
падение, сколько замечаний из ревью принято и — главное — какие были
шумом. Последнее решает, остаётся ли шаг после обучения.

## Подпись вручную

`fastlane package` оставляет `.ipa` без подписи, и на устройство он не встаёт.
`scripts/sign.sh` (или `bundle exec fastlane sign`) доводит его до рабочего
состояния руками — теми же шагами, которые Xcode делает молча за галочкой
Automatic. Скрипт нарочно многословный: каждый шаг печатает, что нашёл и
почему выбрал именно это.

Отправная точка — профиль. Это plist в CMS-конверте с подписью Apple;
`security cms -D` его разворачивает, и внутри видно, для какого app id он
выписан, какая команда, сколько устройств, до какого числа и какие
entitlements разрешено просить. Скрипт ищет профиль по bundle id приложения в
двух местах — Xcode 16 и новее складывает их в
`~/Library/Developer/Xcode/UserData/Provisioning Profiles`, старые версии в
`~/Library/MobileDevice/Provisioning Profiles` — и берёт тот, что дольше
годен.

Из профиля берутся две вещи. Entitlements — их нельзя придумать самому:
устройство сверит то, что легло в подпись, с тем, что разрешено в профиле, и
при расхождении откажет в установке. И сертификат — он лежит внутри профиля в
DER, по нему считается отпечаток SHA-1 и ищется в keychain. Подпись идёт по
отпечатку, а не по имени: имя «Apple Development: …» может совпасть у двух
сертификатов, отпечаток нет. Если сертификат в keychain не нашёлся — значит,
нет и приватного ключа, и подписывать нечем; так бывает после переезда на
другой мак.

Дальше сама подпись. Профиль копируется в `.app` под именем
`embedded.mobileprovision` — оттуда iOS при установке узнаёт, кому и на какие
устройства это можно. Подписывается изнутри наружу: сначала вложенные
фреймворки и dylib, потом приложение, иначе внешняя подпись не сойдётся с
содержимым. В конце `codesign --verify --strict` — та же проверка, что сделает
устройство, — и `codesign -d --entitlements :-`, чтобы увидеть глазами, какие
права реально легли в подпись.

Полезно сломать и посмотреть. Дописать байт в любой ресурс —
`codesign --verify` скажет «a sealed resource is missing or invalid» и назовёт
файл. Поправить байт в самом бинаре — «invalid signature (code or signature
have been modified)». А вот `PkgInfo` можно менять свободно: он не входит в
опечатанные ресурсы, и это хороший пример того, что подпись покрывает не
папку целиком, а список по правилам.

Бесплатный аккаунт ограничивает две вещи. Портала с сертификатами нет, так что
шаг «сгенерировать CSR через `openssl` и выпустить сертификат» воспроизвести
негде — Apple Development сертификат и профиль создаёт Xcode при первом
запуске на телефоне, и скрипт пользуется ими. И профиль живёт семь дней:
просрочился — запускаешь приложение из Xcode на устройстве, он выпишет новый.
Скрипт это проверяет и говорит прямо.

В CI всё это не работает, и это тоже часть картины: на раннере нет ни
сертификата, ни ключа. Чтобы подписывать там, сертификат с ключом экспортируют
в `.p12`, кладут в секрет в base64, на раннере создают временный keychain,
`security import` туда, `security set-key-partition-list`, чтобы `codesign`
мог брать ключ без диалога, — и после сборки keychain удаляют. Ровно это и
прячет `fastlane match`, только ещё хранит `.p12` и профили в зашифрованном
git-репозитории. Понимание ручного пути нужно как раз затем, чтобы, когда
match упадёт, читать его ошибку, а не гадать.

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
