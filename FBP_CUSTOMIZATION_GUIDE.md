# FBP Desk — руководство по кастомизации

Документ описывает, где в репозитории менять иконки, локализацию, проверку обновлений, серверы по умолчанию, WebSocket в Windows-службе и overlay во Flutter UI.

---

## 1. Замена иконок приложения

В RustDesk/FBP Desk иконки задаются **в нескольких независимых местах**. Замена только `res/icon.png` не обновит всё автоматически — нужно пройти все поверхности, которые вы используете.

### 1.1. Карта: где какая иконка используется

| Поверхность | Файл-источник | Куда попадает | Когда меняется |
|---|---|---|---|
| Иконка `.exe` в проводнике | `flutter/windows/runner/resources/app_icon.ico` | Вшивается через `Runner.rc` | После `flutter_launcher_icons` + rebuild Flutter |
| Панель задач / заголовок окна | `flutter/assets/icon.ico` → `data/flutter_assets/assets/icon.ico` | `flutter/windows/runner/win32_window.cpp` | После сборки Flutter bundle |
| Системный трей (Windows) | 1) `data/flutter_assets/assets/icon.png` 2) fallback `res/tray-icon.ico` | `src/tray.rs` | PNG — из bundle; ICO — compile-time embed |
| UI внутри Flutter | `flutter/assets/icon.png`, `logo.png`, `icon.svg` | `loadIcon()`, `loadLogo()` в `flutter/lib/common.dart` | Положить файлы в `flutter/assets/` |
| Rust-сервис / portable / MSI | `res/icon.ico` | `build.rs`, `libs/portable/build.rs`, `res/msi/` | После `res/gen_icon.sh` + rebuild Rust |
| Метаданные exe (не иконка) | `Cargo.toml`, `Runner.rc` | ProductName, FileDescription | Текст брендинга |

### 1.2. Мастер-файлы (начать отсюда)

```
res/icon.png          — главный PNG (1024×1024 или больше)
res/tray-icon.ico     — отдельная иконка для трея (рекомендуется упрощённая)
res/mac-icon.png      — macOS (если нужен)
res/mac-tray-dark-x2.png — macOS tray
```

Конфиг генератора иконок: `flutter/pubspec.yaml` → секция `flutter_icons`:

```yaml
flutter_icons:
  image_path: "../res/icon.png"
  windows:
    generate: true
  # ...
```

### 1.3. Пошагово: Windows Flutter desktop

**Шаг 1.** Замените `res/icon.png` своим логотипом.

**Шаг 2.** Сгенерируйте `res/icon.ico` для Rust/MSI/portable:

```bash
cd res
# Нужен ImageMagick; скрипт: res/gen_icon.sh
bash gen_icon.sh
# или вручную экспортируйте multi-size .ico в res/icon.ico
```

**Шаг 3.** (Опционально) Замените `res/tray-icon.ico` — отдельная иконка для notification area.

**Шаг 4.** Сгенерируйте платформенные иконки Flutter:

```bash
cd flutter
dart run flutter_launcher_icons
```

Результат должен обновить минимум:
- `flutter/windows/runner/resources/app_icon.ico`
- иконки Android/iOS/Linux/web (по конфигу)

**Шаг 5.** Положите in-app ассеты в `flutter/assets/`:

```
flutter/assets/icon.png   — маленькая иконка в UI
flutter/assets/logo.png   — логотип в шапке (loadLogo)
flutter/assets/icon.svg   — fallback, если PNG не найден
flutter/assets/icon.ico   — для taskbar override (попадёт в bundle)
```

Папка подключена в `flutter/pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/
```

**Шаг 6.** Пересоберите:

```bash
python3 build.py --flutter --release
# или полный CI-пайплайн
```

**Шаг 7.** Проверка после сборки:

| Что проверить | Где смотреть |
|---|---|
| Иконка exe | Проводник → `rustdesk.exe` |
| Taskbar | Запущенное окно |
| Трей | Иконка у часов (нужна служба) |
| UI | Логотип на главной странице |
| Portable exe | `libs/portable` → icon из `res/icon.ico` |

### 1.4. Код, который читает иконки

**Трей** — `src/tray.rs`:

```rust
// Сначала ищет runtime-файл:
//   {exe_dir}/data/flutter_assets/assets/icon.png
// Иначе — встроенный res/tray-icon.ico (include_bytes!)
icon = include_bytes!("../res/tray-icon.ico");
```

**Flutter UI** — `flutter/lib/common.dart`:

```dart
Widget loadIcon(double size) => Image.asset('assets/icon.png', ...);
Widget loadLogo() => rootBundle.load('assets/logo.png');
```

**Windows runner** — `flutter/windows/runner/Runner.rc`:

```
IDI_APP_ICON  ICON  "resources\\app_icon.ico"
```

**Rust winres** (inline/release) — `build.rs`:

```rust
res.set_icon("res/icon.ico")
```

### 1.5. Частые ошибки

- **Трей остался старым** — не обновили `res/tray-icon.ico` и не пересобрали Rust, или в bundle нет `assets/icon.png`.
- **Exe-иконка старая, UI новая** — не запустили `flutter_launcher_icons` (обновляет `app_icon.ico`, не только PNG).
- **Portable/MSI со старой иконкой** — не обновили `res/icon.ico`.

---

## 2. Локализация: свои строки во Flutter

### 2.1. Как устроено (важно)

В этом проекте **нет** Flutter `.arb` / `intl` генерации. Строки хранятся в **Rust**, Flutter получает их через FFI:

```
Flutter: translate("KEY")
    → platformFFI.translate(name, localeName)     // flutter/lib/common.dart
    → flutter_ffi.rs::translate()
    → src/lang.rs::translate_locale()
    → HashMap в src/lang/en.rs, ru.rs, be.rs, ...
```

Язык пользователя: локальная опция `lang` + список `LANGS` в `src/lang.rs`.

### 2.2. Файлы локализации

| Файл | Назначение |
|---|---|
| `src/lang/template.rs` | Список всех ключей (мастер) |
| `src/lang/en.rs` | Английский (эталон перевода) |
| `src/lang/ru.rs` | Русский |
| `src/lang/be.rs` | Белорусский |
| `src/lang.rs` | Регистрация языков, `translate_locale()` |
| `res/lang.py` | Синхронизация ключей между языками |

Формат записи (см. `src/lang/README.md`):

```rust
("YourKey", "English text"),
```

FBP уже добавлял свои строки, например в `src/lang/en.rs`:

```rust
("connecting_status", "Connecting to the FBPDesk network..."),
```

### 2.3. Как добавить новую строку

**1.** Добавьте ключ в `src/lang/template.rs`:

```rust
("FBP License Required", ""),
```

**2.** Добавьте переводы в языковые файлы:

`src/lang/en.rs`:
```rust
("FBP License Required", "A valid license is required to connect."),
```

`src/lang/ru.rs`:
```rust
("FBP License Required", "Для подключения требуется действующая лицензия."),
```

**3.** (Опционально) Синхронизируйте все языки скриптом:

```bash
python res/lang.py
```

Скрипт добавит новые ключи из `template.rs` во все `.rs` файлы в `src/lang/`.

**4.** Если добавляете **новый язык** — создайте `src/lang/xx.rs`, подключите модуль и запись в `LANGS` в `src/lang.rs`.

**5.** В Flutter используйте:

```dart
Text(translate('FBP License Required'))
```

Ключ — **английская строка-ключ** из первого поля tuple, не сгенерированный ID.

### 2.4. Пересборка после изменений

Строки компилируются в Rust-бинарник:

```bash
# Пересобрать Rust + Flutter
python3 build.py --flutter
```

Hot reload **не** подхватит изменения в `src/lang/*.rs` — нужна полная пересборка Rust.

### 2.5. Flutter-only строки (без Rust)

Если строка нужна **только** во Flutter и не должна идти через FFI — можно оставить литерал или завести свой Dart-map (как `const url = 'https://1c-fbp.ru/pricing'` в `connection_page.dart`). Но для единообразия с остальным UI лучше добавлять в Rust lang-файлы.

---

## 3. Проверка обновлений — где логика и как заменить

### 3.1. Цепочка вызовов

```
Старт приложения
  flutter/lib/main.dart → checkUpdate()
    flutter/lib/common.dart → bind.mainGetSoftwareUpdateUrl()
      src/flutter_ffi.rs → check_software_update()
        src/common.rs → do_check_software_update()  [async HTTP POST]
          → событие "check_software_update_finish" с url
            → stateGlobal.updateUrl во Flutter
```

**Авто-обновление (Windows, установленная служба):**

```
src/rendezvous_mediator.rs::start_all()
  → src/updater.rs::start_auto_update()   [фоновый цикл, раз в сутки]
```

### 3.2. Ключевые файлы

| Файл | Что делает |
|---|---|
| `src/common.rs` | `check_software_update()`, `do_check_software_update()` — HTTP к API версий |
| `src/updater.rs` | Скачивание и установка обновления (Windows service) |
| `src/flutter_ffi.rs` | FFI `main_get_software_update_url()` |
| `flutter/lib/common.dart` | `checkUpdate()`, обработчик события |
| `flutter/lib/consts.dart` | `kCheckSoftwareUpdateFinish`, `kOptionEnableCheckUpdate` |
| `flutter/lib/models/state_model.dart` | `stateGlobal.updateUrl` |
| `flutter/lib/desktop/widgets/update_progress.dart` | UI установки обновления |
| `flutter/lib/desktop/pages/desktop_home_page.dart` | Карточка «доступно обновление» + hardcoded download URL |

### 3.3. Конфиг-ключи

| Ключ | Значение |
|---|---|
| `enable-check-update` | Включить проверку при старте |
| `allow-auto-update` | Авто-скачивание (Windows service, `updater.rs`) |

### 3.4. Поведение FBPDesk (уже есть)

**Проверка отключена для custom client:**

```rust
// src/common.rs
pub fn check_software_update() {
    if is_custom_client() {  // get_app_name() != "RustDesk"
        return;
    }
    // ...
}

pub fn is_custom_client() -> bool {
    get_app_name() != "RustDesk"
}
```

После `init_fbp_app_name()` app name = `"FBPDesk"` → **стандартная проверка rustdesk.com не запускается**.

Flutter тоже проверяет:

```dart
// flutter/lib/common.dart
void checkUpdate() {
  if (!bind.isCustomClient()) {  // false для FBPDesk
    // ...
  }
}
```

### 3.5. Как реализовать **свою** проверку обновлений

**Вариант A — только Flutter (быстро):**

1. В `flutter/lib/main.dart` вызвать свою функцию вместо/рядом с `checkUpdate()`.
2. HTTP к своему API (`https://remote.1c-fbp.ru/api/version` или аналог).
3. Записать URL в `stateGlobal.updateUrl.value` — UI подхватит существующие карточки.

**Вариант B — через Rust (как upstream):**

1. Изменить `do_check_software_update()` в `src/common.rs`:
   - заменить URL (сейчас через `hbb_common::version_check_request`, комментарий указывает на `api.rustdesk.com`);
   - или убрать guard `is_custom_client()` и подставить свой endpoint.
2. При необходимости изменить `src/updater.rs` для скачивания с вашего сервера.

**Вариант C — hardcoded ссылки (уже частично есть):**

В `desktop_home_page.dart` уже есть:

```dart
final Uri url = Uri.parse('https://remote.1c-fbp.ru/download');
```

Можно расширить эту логику для кнопки «Скачать обновление».

**Вариант D — полностью отключить:**

Ничего не делать — для FBPDesk проверка уже пропускается. Дополнительно можно выставить `enable-check-update=N` в default-settings (см. раздел 4).

---

## 4. Relay / ID сервер по умолчанию

### 4.1. Ключи конфигурации

| Ключ | Назначение |
|---|---|
| `custom-rendezvous-server` | ID / rendezvous сервер (hbbs) |
| `relay-server` | Relay сервер (hbbr) |
| `api-server` | API / аккаунты / heartbeat |
| `key` | Публичный ключ сервера |
| `rendezvous-servers` | Список от сервера (заполняется автоматически) |

Flutter читает/пишет через `ServerConfig` в `flutter/lib/common.dart`:

```dart
ServerConfig.fromOptions(...)  // custom-rendezvous-server, relay-server, ...
setServerConfig(config)        // bind.mainSetOption(...)
```

UI настроек: **Settings → Network → ID/Relay Server** (`desktop_setting_page.dart` → `showServerSettings`).

### 4.2. Порядок выбора сервера (Rust)

```
1. Windows license из имени exe     → src/platform/windows.rs
2. custom-rendezvous-server (user)  → Config / OPTIONS
3. PROD_RENDEZVOUS_SERVER (compile) → libs/hbb_common/src/config.rs
4. DEFAULT_SETTINGS (custom client) → из signed custom.txt
5. RENDEZVOUS_SERVERS (upstream)    → ["rs-ny.rustdesk.com"] по умолчанию
```

Relay (`src/rendezvous_mediator.rs`, `get_relay_server`):

```
1. relay-server (user option)
2. relay от rendezvous сервера
3. ID host + 1 порт (fallback)
```

### 4.3. Способы задать **ваши** серверы по умолчанию

#### Способ 1 — Код в `init_fbp_app_name()` (простой для форка)

Файл: `src/common.rs`

```rust
pub fn init_fbp_app_name() {
    if hbb_common::config::APP_NAME.read().unwrap().eq("RustDesk") {
        *hbb_common::config::APP_NAME.write().unwrap() = "FBPDesk".to_owned();
    }
    // Добавить: defaults только если пользователь ещё не настраивал
    use hbb_common::config::Config;
    if Config::get_option("custom-rendezvous-server").is_empty() {
        Config::set_option("custom-rendezvous-server".into(), "your-hbbs.example.com".into());
    }
    if Config::get_option("relay-server").is_empty() {
        Config::set_option("relay-server".into(), "your-hbbr.example.com".into());
    }
    if Config::get_option("key").is_empty() {
        Config::set_option("key".into(), "YOUR_BASE64_PUBLIC_KEY".into());
    }
}
```

Вызывается из `load_custom_client()` и `flutter_ffi.rs` при старте Flutter.

#### Способ 2 — `DEFAULT_SETTINGS` через signed `custom.txt`

Файл: `src/common.rs` → `read_custom_client()`

Upstream OEM-клиенты используют подписанный base64 JSON рядом с exe:

```
{exe_dir}/custom.txt
```

Структура JSON (упрощённо):

```json
{
  "app-name": "FBPDesk",
  "default-settings": {
    "custom-rendezvous-server": "hbbs.example.com",
    "relay-server": "hbbr.example.com",
    "api-server": "https://api.example.com",
    "key": "..."
  },
  "override-settings": {},
  "disable-settings": "Y"
}
```

Файл **подписывается** ключом RustDesk OEM (`read_custom_client` → `sign::verify`). Для dev/debug можно положить незашифрованный `./custom.txt` в корень проекта — читается только в **debug** сборке:

```rust
#[cfg(debug_assertions)]
if let Ok(data) = std::fs::read_to_string("./custom.txt") {
    read_custom_client(data.trim());  // всё равно нужна подпись для read_custom_client
}
```

Для production без OEM-подписи используйте **Способ 1** или **3**.

#### Способ 3 — Compile-time `PROD_RENDEZVOUS_SERVER`

В `libs/hbb_common/src/config.rs` (submodule) задаётся при сборке. Требует форка/патча hbb_common.

#### Способ 4 — Windows license в имени exe

При установке с правами администратора (`src/core_main.rs`):

```
rustdesk.exe --install your-encoded-license.exe
```

Декодирует host/relay/api/key из имени файла (`src/custom_server.rs`, `src/platform/windows.rs`).

#### Способ 5 — CLI при установке службы

```bash
rustdesk.exe --option custom-rendezvous-server your.server.com
```

(Требует installed + admin — `core_main.rs`.)

### 4.4. Где хранится конфиг пользователя (Windows)

```
%APPDATA%\FBPDesk\config\RustDesk2.toml    # после init_fbp_app_name
%APPDATA%\FBPDesk\config\RustDesk_local.toml
```

Имя файлов исторически `RustDesk*.toml`, путь — `%APPDATA%\FBPDesk\`.

### 4.5. Проверка

- UI: Settings → Network → ID/Relay Server
- Rust log: rendezvous registration в `src/rendezvous_mediator.rs`
- `bind.mainIsUsingPublicServer()` — `false`, если задан custom server

---

## 5. WebSocket в Rust (Windows служба)

### 5.1. Архитектура процессов Windows

```
Windows Service (--service)
  src/platform/windows.rs → run_service()
    └─ supervisor loop (~300 ms)
         └─ spawn: rustdesk.exe --server

Server process (--server)
  src/server.rs → start_server(is_server: true)
    ├─ ipc::start("")                    # IPC с UI/другими процессами
    └─ RendezvousMediator::start_all()   # основной сетевой event loop
         ├─ hbbs_http::sync::start()
         ├─ updater::start_auto_update()  # Windows installed
         └─ регистрация на hbbs / relay
```

**Важно:** Windows SCM service (`run_service`) — только **надзиратель** за процессом `--server`. Сетевую логику туда не добавляют.

### 5.2. Существующий WebSocket в протоколе RustDesk

WebSocket уже используется для **rendezvous/relay**, не как отдельный «ваш» канал:

| Место | Роль |
|---|---|
| `libs/hbb_common` (`use_ws()`, `socket_client::connect_tcp`) | Транспорт WS/TCP |
| `src/client.rs` | `use_ws()` при подключении к peer |
| `src/rendezvous_mediator.rs` | relay через WS если `use_ws()` |
| `src/common.rs` | `secure_tcp_impl` — иная обработка при WS |
| Config key `allow-websocket` | Включение WS транспорта |

Toggle в UI: Settings → Network → «Use WebSocket» (`desktop_setting_page.dart`, ключ `kOptionAllowWebSocket`).

### 5.3. Куда добавить **свой** WebSocket (например, к вашему backend)

**Рекомендуемая точка входа:**

```rust
// src/server.rs — в start_server(), блок if is_server { ... }
#[cfg(target_os = "windows")]
if crate::platform::is_installed() && crate::is_server() {
    tokio::spawn(async {
        if let Err(e) = crate::your_module::ws_client_loop().await {
            log::error!("ws client error: {}", e);
        }
    });
}
crate::RendezvousMediator::start_all().await;
```

**Новый модуль** (например `src/fbp_ws.rs`):

- `tokio-tungstenite` уже в зависимостях через `hbb_common`
- reconnect loop пока `is_server()` / служба запущена
- обмен с Flutter через `flutter::push_global_event()` или `ipc::Data`

**Альтернатива — рядом с heartbeat:**

`src/hbbs_http/sync.rs` уже ходит на `{api-server}/api/heartbeat`. Можно расширить sync или добавить параллельный WS к тому же API.

**Не добавлять WS в:**

- `run_service()` loop — слишком короткий tick, нет tokio runtime context для долгих соединений
- UI process — умрёт при закрытии окна; служба `--server` живёт постоянно

### 5.4. Связь WS ↔ Flutter UI

```
Rust server  --push_global_event-->  Flutter EventToUI  -->  Dart handler
Rust server  --ipc::Data-->          UI process           -->  bind / model
```

Примеры event dispatch: `src/common.rs` (`check_software_update_finish`), `flutter/lib/models/model.dart`.

### 5.5. Минимальный скелет

```rust
// src/fbp_ws.rs
pub async fn ws_client_loop() -> hbb_common::ResultType<()> {
    loop {
        if !crate::is_server() {
            break;
        }
        match connect_and_run("wss://your-backend.example/ws").await {
            Ok(_) => {}
            Err(e) => log::error!("ws disconnected: {}", e),
        }
        hbb_common::tokio::time::sleep(std::time::Duration::from_secs(5)).await;
    }
    Ok(())
}
```

Подключить модуль в `src/lib.rs` и spawn из `start_server()`.

---

## 6. Flutter: overlay («замок») поверх UI

### 6.1. Контекст: `ConnectionPage` в `desktop_home_page.dart`

Сейчас правая панель:

```dart
buildRightPane(BuildContext context) {
  return Container(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: ConnectionPage(),
  );
}
```

`ConnectionPage` (`flutter/lib/desktop/pages/connection_page.dart`) — обычный `Column` без overlay.

Вся домашняя страница уже обёрнута в `buildRemoteBlock()` (блокировка при активной remote-сессии):

```dart
// desktop_home_page.dart
Widget _buildBlock({required Widget child}) {
  return buildRemoteBlock(
      block: _block, mask: true, use: canBeBlocked, child: child);
}
```

### 6.2. Паттерны overlay в этом проекте

| Паттерн | Где используется | Когда применять |
|---|---|---|
| `Stack` + `Positioned.fill` | `desktop_setting_page.dart`, `desktop_home_page.dart` | Локальный overlay на части экрана |
| `buildRemoteBlock()` | `common.dart`, home/settings | Блокировка input + полупрозрачная маска |
| `Overlay` + `OverlayEntry` | `common/widgets/overlay.dart`, `file_manager_page.dart` | Плавающие диалоги, draggable chat |
| `OverlayDialogManager` | `common.dart` | Модальные окна с затемнением |

`ModalBarrier` в проекте **не используется** — вместо него `Container(color: Colors.black.withOpacity(0.5))`.

### 6.3. Вариант A — overlay только над `ConnectionPage` (рекомендуется)

Изменить `buildRightPane` в `desktop_home_page.dart`:

```dart
buildRightPane(BuildContext context) {
  final isLocked = false; // заменить на RxBool / Provider / ваш state

  return Container(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Stack(
      children: [
        ConnectionPage(),
        if (isLocked)
          Positioned.fill(
            child: AbsorbPointer(
              child: Container(
                color: Colors.black.withOpacity(0.45),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 48, color: Colors.white70),
                      SizedBox(height: 12),
                      Text(
                        translate('FBP License Required'),
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
```

- `AbsorbPointer` — блокирует клики по полям под overlay
- `Positioned.fill` — покрывает только правую панель, левая (ID board) остаётся доступной

### 6.4. Вариант B — reactive overlay через GetX (как в проекте)

```dart
// В state model или отдельный RxBool
final RxBool connectionLocked = false.obs;

buildRightPane(BuildContext context) {
  return Container(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Obx(() => Stack(
      children: [
        ConnectionPage(),
        if (connectionLocked.value) _buildLockOverlay(context),
      ],
    )),
  );
}
```

Переключать `connectionLocked.value = true` из Rust event, license check и т.д.

### 6.5. Вариант C — overlay внутри `ConnectionPage`

Если замок относится только к полю ввода ID — обернуть `Column` в `connection_page.dart`:

```dart
@override
Widget build(BuildContext context) {
  return Stack(
    children: [
      Column(/* существующий контент */),
      if (_locked) _lockLayer(context),
    ],
  );
}
```

Плюс: инкапсуляция. Минус: не покрывает соседние элементы home page.

### 6.6. Вариант D — переиспользовать `buildRemoteBlock`

Если нужно заблокировать **всю** home page (как при remote session):

```dart
return buildRemoteBlock(
  block: _licenseBlock,
  mask: true,
  child: Row(...),
);
```

Логика блокировки: `flutter/lib/common.dart` → `buildRemoteBlock`, `preventMouseKeyBuilder`.

Пример с маской в settings: `desktop_setting_page.dart` → `_buildBlock()`.

### 6.7. Вариант E — модальный диалог поверх всего окна

```dart
OverlayDialogManager.show(
  (overlayContext, close) => Center(
    child: Card(
      child: /* содержимое замка */,
    ),
  ),
);
```

Требует `OverlayState` — в main window используется `globalKey` из `flutter/lib/main.dart`.

### 6.8. Связь overlay с Rust (license gate)

1. Rust проверяет лицензию в `--server` или при connect.
2. Отправляет event во Flutter:

```rust
// push event
m.insert("name", "fbp_license_locked");
m.insert("locked", "true");
flutter::push_global_event(APP_TYPE_MAIN, json);
```

3. Flutter регистрирует handler (как `checkUpdate`):

```dart
platformFFI.registerEventHandler('fbp_license_locked', 'fbp_license_locked',
  (evt) async {
    connectionLocked.value = evt['locked'] == 'true';
});
```

### 5.6. Передача `token` и `device_id` в query WebSocket

После активации устройства Flutter сохраняет пару в **локальный конфиг** (`RustDesk_local.toml`, см. раздел 8). Rust-модуль WS читает их через `LocalConfig::get_option()` и подставляет в URL при handshake.

**Рекомендуемые ключи конфига:**

| Ключ | Значение |
|---|---|
| `device_activation_token` | `token` от бэкенда |
| `device_activation_device_id` | `deviceid` (GUID) от бэкенда |

**Rust — сборка URL:**

```rust
use hbb_common::config::LocalConfig;
use url::Url;

const KEY_TOKEN: &str = "device_activation_token";
const KEY_DEVICE_ID: &str = "device_activation_device_id";

fn build_ws_url(base: &str) -> Option<String> {
    let token = LocalConfig::get_option(KEY_TOKEN);
    let device_id = LocalConfig::get_option(KEY_DEVICE_ID);
    if token.is_empty() || device_id.is_empty() {
        return None; // устройство не активировано — WS не поднимаем
    }
    let mut url = Url::parse(base).ok()?;
    url.query_pairs_mut()
        .append_pair("device_id", &device_id)
        .append_pair("token", &token);
    Some(url.to_string())
}

// Пример: wss://remote.1c-fbp.ru/ws?device_id=550e8400-...&token=abc123
```

**Альтернатива — заголовки** (если бэкенд читает не query, а headers):

```rust
use tokio_tungstenite::tungstenite::client::IntoClientRequest;

let mut req = url.into_client_request()?;
req.headers_mut().insert("X-Device-Id", device_id.parse()?);
req.headers_mut().insert("X-Token", token.parse()?);
```

На стороне Go/Fiber query обычно читается до upgrade:

```go
deviceID := c.Query("device_id")
token := c.Query("token")
```

Имена параметров (`device_id` / `deviceid`) должны совпадать с тем, что ожидает ваш бэкенд.

### 5.7. WebSocket без установки (portable / «только запущено»)

**Да, это реально**, но с оговорками по процессам Windows.

| Режим | `is_installed()` | Процесс `--server` | Windows SCM service |
|---|---|---|---|
| Установлено + служба | `true` | Да (служба его поднимает) | Да |
| Установлено, служба выкл. | `true` | Да (кнопка «Start service») | Нет |
| Portable / exe из папки | `false` | **Да** (кнопка «Start service») | Нет |
| Только UI, служба остановлена | любой | Нет | — |

- `bind.mainIsInstalled()` / `platform::is_installed()` — exe лежит в каталоге установки (реестр Windows).
- `isRunningInPortableMode()` (`flutter/lib/common.dart`) — portable-сборка (env `RUSTDESK_EXECUTABLE`).
- Сетевой фон живёт в процессе **`rustdesk.exe --server`**, не в окне Flutter. UI может закрыться — WS останется, только если `--server` запущен.

**Где spawn WS-клиента:**

```rust
// src/server.rs — внутри start_server(), когда is_server == true
// НЕ ограничивать только is_installed(), иначе portable не получит WS
if crate::is_server() {
    tokio::spawn(async {
        if let Err(e) = crate::fbp_ws::ws_client_loop().await {
            log::error!("fbp ws: {}", e);
        }
    });
}
crate::RendezvousMediator::start_all().await;
```

Пользователь без установки нажимает **Start service** (`connection_page.dart` → `start_service(true)`), что снимает `stop-service` и поднимает `--server`. После этого WS-модуль может работать.

**Ограничение:** без `--server` (служба остановлена, portable не стартовал сервис) — WS из Rust **не запустится**, даже если окно Flutter открыто.

### 5.8. Обрыв WebSocket и ошибки с сервера

#### Отказ при handshake (401 / Blocked)

Если бэкенд **не делает upgrade** и отвечает HTTP-ошибкой (как в вашем Fiber-примере), `connect_async` / `client_async` завершится ошибкой **до** установки WS-соединения.

```go
// Сервер отклоняет до upgrade:
return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "Blocked"})
```

В Rust:

```rust
match tokio_tungstenite::connect_async(ws_url).await {
    Err(e) => {
        // Часто: HTTP error: 401 Unauthorized
        log::error!("ws handshake failed: {}", e);
        // Опционально: разобрать тело ответа через client_async_with_config + custom connector
        notify_flutter_ws_error("Blocked", "Token invalid or device blocked");
    }
    Ok((mut stream, _resp)) => { /* читать/писать кадры */ }
}
```

Для чтения JSON-тела при 401 удобнее низкоуровневый HTTP GET/POST к тому же endpoint или `tokio_tungstenite` с кастомным connector, который логирует `response.status()` и body.

#### Разрыв после установки соединения

| Событие | Как поймать в Rust |
|---|---|
| Сервер закрыл соединение | `read.next().await` → `None` или `Err(ConnectionClosed)` |
| Сетевой обрыв | `Err(Io(...))`, `Protocol(ResetWithoutClosingHandshake)` |
| Ping timeout | свой watchdog + `stream.send(Ping(...))` |
| Сервер прислал Close frame | `Message::Close(Some(frame))` — в `frame.reason` может быть текст |

```rust
use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::tungstenite::Message;

while let Some(msg) = stream.next().await {
    match msg {
        Ok(Message::Close(frame)) => {
            let reason = frame.map(|f| f.reason.to_string()).unwrap_or_default();
            log::warn!("ws closed by server: {}", reason);
            notify_flutter_ws_error("closed", &reason);
            break;
        }
        Ok(Message::Text(text)) => {
            // {"error":"Blocked"} — если сервер шлёт ошибку в кадре перед close
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                if v.get("error").is_some() {
                    notify_flutter_ws_error(v["error"].as_str().unwrap_or("error"), &text);
                }
            }
        }
        Err(e) => {
            log::error!("ws read error: {}", e);
            notify_flutter_ws_error("io_error", &e.to_string());
            break;
        }
        _ => {}
    }
}
```

#### Уведомление Flutter

```rust
fn notify_flutter_ws_error(code: &str, detail: &str) {
    let mut m = serde_json::Map::new();
    m.insert("name".into(), json!("fbp_ws_status"));
    m.insert("status".into(), json!("error"));
    m.insert("code".into(), json!(code));
    m.insert("detail".into(), json!(detail));
    crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, json!(m));
}
```

```dart
// flutter/lib/main.dart → _registerEventHandler()
platformFFI.registerEventHandler('fbp_ws_status', 'fbp_ws_status', (evt) async {
  final code = evt['code'] ?? '';
  // connectionLocked, snackbar, overlay и т.д.
});
```

Reconnect loop в `ws_client_loop` с backoff (5–30 с) — стандартная практика; при `Blocked` можно **не** ретраить, а сбросить активацию в UI.

---

## 7. Цвета Flutter UI (один файл)

### 7.1. Где сейчас лежат цвета

| Место | Что задаёт |
|---|---|
| `flutter/lib/common.dart` → `MyTheme` | **Главная тема**: `accent`, `grayBg`, `button`, `lightTheme`, `darkTheme` |
| `flutter/lib/common.dart` → `ColorThemeExtension` | Границы, toast, divider (light/dark) |
| `flutter/lib/consts.dart` | `kColorWarn`, `kColorCanvas` |
| Отдельные экраны | Hardcoded цвета, напр. `Color.fromARGB(255, 50, 190, 166)` в `device_activation.dart`, `connection_page.dart` |

Тема подключается в `flutter/lib/main.dart`:

```dart
theme: MyTheme.lightTheme,
darkTheme: MyTheme.darkTheme,
```

### 7.2. Рекомендация: один файл бренда

Создайте `flutter/lib/custom/fbp_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Все FBP-цвета бренда — менять только здесь.
abstract final class FbpColors {
  static const Color primary = Color(0xFF32BEA6);   // #32BEA6 — статус «готово»
  static const Color accent = Color(0xFF0071FF);      // кнопки, ссылки
  static const Color accentButton = Color(0xFF2C8CFF);
  static const Color warn = Color(0xFFF5853B);
  static const Color error = Color(0xFFE04F5F);
  static const Color grayBg = Color(0xFFEFEFF2);
  static const Color idHighlight = Color(0xFF00B6F0);
}
```

Затем в `MyTheme` (`common.dart`) замените константы:

```dart
static const Color accent = FbpColors.accent;
static const Color button = FbpColors.accentButton;
// elevatedButtonTheme → backgroundColor: FbpColors.accent
```

И уберите дубли в кастомных экранах:

```dart
// device_activation.dart, connection_page.dart
color: FbpColors.primary  // вместо Color.fromARGB(255, 50, 190, 166)
```

**Минимальный путь без нового файла:** править только блок `class MyTheme` в `common.dart` (строки ~253–264 и `elevatedButtonTheme` / `colorScheme` в `lightTheme`/`darkTheme`). Но hardcoded цвета в `custom/` и `connection_page.dart` придётся менять вручную.

### 7.3. Чеклист после смены палитры

1. Светлая и тёмная тема (`MyTheme.lightTheme` / `darkTheme`).
2. `ColorThemeExtension.light` / `.dark` — если нужны другие border/toast.
3. `consts.dart` — `kColorWarn` и др.
4. Grep по `0x32BEA6`, `50, 190, 166`, `0x0071FF` — найти забытые hardcode.
5. Перезапуск приложения (hot reload подхватит Dart, но не Rust).

---

## 8. Активация устройства: `deviceid`, `token`, Flutter state

### 8.1. Проблема в текущем `device_activation.dart`

Сейчас:

- Сохраняется только `device_activation_token`.
- На экране «активировано» показывается `bind.mainGetMyId()` — это **RustDesk peer ID** (короткий ID для удалённого подключения), **не** GUID с бэкенда.

Бэкенд при активации возвращает:

```json
{
  "deviceid": "550e8400-e29b-41d4-a716-446655440000",
  "token": "secret-token-string"
}
```

Оба поля нужно сохранить; пользователю показывать **`deviceid`**.

### 8.2. Ключи конфигурации

| Ключ | Назначение |
|---|---|
| `device_activation_token` | Секрет для WS/API |
| `device_activation_device_id` | GUID устройства в вашей системе |

Хранятся в `%APPDATA%\FBPDesk\config\RustDesk_local.toml` через FFI:

```dart
await bind.mainSetLocalOption(key: 'device_activation_token', value: token);
await bind.mainSetLocalOption(key: 'device_activation_device_id', value: deviceId);
```

Чтение:

```dart
final token = bind.mainGetLocalOption(key: 'device_activation_token');
final deviceId = bind.mainGetLocalOption(key: 'device_activation_device_id');
final isActivated = token.isNotEmpty && deviceId.isNotEmpty;
```

`bind.mainGetMyId()` — оставить для RustDesk-сети (поле «Ваш ID» на главной), **не** подменять им `deviceid` активации.

### 8.3. Логика активации (псевдокод)

```dart
final response = await http.post(
  Uri.parse('${CustomConfig.getActivationApiUrl()}/api/activate'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'code': code}), // device_id с клиента не обязателен — сервер выдаёт GUID
);

if (response.statusCode == 200) {
  final data = jsonDecode(response.body);
  final token = data['token'] as String;
  final deviceId = data['deviceid'] as String; // или data['device_id'] — как в API

  await bind.mainSetLocalOption(key: kCommConfKeyDeviceToken, value: token);
  await bind.mainSetLocalOption(key: kCommConfKeyDeviceId, value: deviceId);

  DeviceActivationState.find.reload();
}
```

Константы вынести в `flutter/lib/custom/config.dart` рядом с `CustomConfig`.

### 8.4. Глобальный Flutter state (для `device_activation` и `connection_page`)

Паттерн как у `access_token` в `login.dart` / `toolbar.dart`: конфиг в Rust — источник истины, во Flutter — реактивная обёртка.

**Файл `flutter/lib/custom/device_activation_state.dart`:**

```dart
import 'package:get/get.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/custom/config.dart';

class DeviceActivationState extends GetxController {
  static DeviceActivationState get find => Get.put(DeviceActivationState(), permanent: true);

  final isActivated = false.obs;
  final deviceId = ''.obs;
  final token = ''.obs;

  @override
  void onInit() {
    super.onInit();
    reload();
  }

  void reload() {
    token.value = bind.mainGetLocalOption(key: CustomConfig.kDeviceTokenKey);
    deviceId.value = bind.mainGetLocalOption(key: CustomConfig.kDeviceIdKey);
    isActivated.value = token.value.isNotEmpty && deviceId.value.isNotEmpty;
  }

  Future<void> save({required String token, required String deviceId}) async {
    await bind.mainSetLocalOption(key: CustomConfig.kDeviceTokenKey, value: token);
    await bind.mainSetLocalOption(key: CustomConfig.kDeviceIdKey, value: deviceId);
    reload();
  }

  Future<void> clear() async {
    await bind.mainSetLocalOption(key: CustomConfig.kDeviceTokenKey, value: '');
    await bind.mainSetLocalOption(key: CustomConfig.kDeviceIdKey, value: '');
    reload();
  }
}
```

**Инициализация** — в `flutter/lib/main.dart` после `Get.put` для `stateGlobal`:

```dart
Get.put(DeviceActivationState(), permanent: true);
```

**`device_activation.dart`:**

```dart
final state = DeviceActivationState.find;

// initState:
state.reload();

// после успешной активации:
await state.save(token: token, deviceId: deviceId);

// UI:
Obx(() => state.isActivated.value ? _buildActivated(state.deviceId.value) : _buildForm());
```

**`connection_page.dart`** — блокировка подключения без активации:

```dart
final activation = DeviceActivationState.find;

Obx(() {
  if (!activation.isActivated.value) {
    return /* overlay или disabled Connect */;
  }
  return /* обычный UI */;
});
```

**Синхронизация с Rust WS:** при событии `fbp_ws_status` + `code == Blocked` вызвать `DeviceActivationState.find.clear()` и показать форму активации.

### 8.5. Деактивация

При `token` invalid / device blocked сервер может закрыть WS. Flutter:

1. Получает event `fbp_ws_status`.
2. `DeviceActivationState.find.clear()` — очищает локальные ключи.
3. UI возвращается к форме ввода кода.

Опционально — HTTP `POST /api/deactivate` перед очисткой локального конфига.

---

## Быстрая шпаргалка путей

```
Иконки:           res/icon.png, res/tray-icon.ico, flutter/assets/
                  flutter/pubspec.yaml (flutter_icons)
                  src/tray.rs, Runner.rc, build.rs

Локализация:      src/lang/template.rs, src/lang/en.rs, src/lang/ru.rs
                  res/lang.py
                  Flutter: translate('Key')

Обновления:       src/common.rs (check/do_check)
                  src/updater.rs, flutter/lib/common.dart (checkUpdate)

Серверы:          src/common.rs (init_fbp_app_name, get_custom_rendezvous_server)
                  src/rendezvous_mediator.rs (relay)
                  flutter/lib/common.dart (ServerConfig, setServerConfig)
                  Config keys: custom-rendezvous-server, relay-server, api-server, key

WebSocket:        src/server.rs (spawn в --server, не только installed)
                  src/fbp_ws.rs (ваш WS к бэкенду)
                  query: device_id + token из LocalConfig
                  события: push_global_event → fbp_ws_status

Цвета Flutter:    flutter/lib/custom/fbp_colors.dart (рекомендуется)
                  flutter/lib/common.dart → MyTheme, ColorThemeExtension
                  flutter/lib/consts.dart → kColorWarn

Активация:        flutter/lib/custom/device_activation.dart
                  flutter/lib/custom/config.dart (ключи)
                  flutter/lib/custom/device_activation_state.dart (state)
                  RustDesk_local.toml: device_activation_token, device_activation_device_id
                  НЕ путать с bind.mainGetMyId() (peer ID RustDesk)

Flutter overlay:  desktop_home_page.dart → buildRightPane + Stack
                  common.dart → buildRemoteBlock
                  connection_page.dart → build + Stack
```
