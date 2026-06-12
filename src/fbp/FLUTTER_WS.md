# FBP WebSocket — интеграция с Flutter

Rust-модуль: `src/fbp/fbp_ws.rs`  
Запускается в процессе `--server` (см. `src/server.rs`).

Логи пишутся через `log::info!` / `log::error!` — туда же, куда и остальной RustDesk/FBP (flexi_logger → файл, если включён в вашей сборке).

---

## 1. Конфигурация (ключи LocalConfig)

| Ключ | Откуда | Назначение |
|---|---|---|
| `device_activation_token` | активация | query `token` |
| `device_activation_device_id` | активация | query `device_id` (GUID) |
| `custom_websocket_url` | UI / `CustomConfig` | базовый URL, default `wss://api.fbpdesk.ru` |

Если `token` или `device_id` пустые — WS **не подключается**, статус `not_activated`.

Итоговый URL: `{base}/ws?device_id=...&token=...` (путь `/ws` добавляется, если в base только хост).

---

## 2. Статусы для UI

| `status` | Когда |
|---|---|
| `not_activated` | нет token/device_id в конфиге |
| `connecting` | идёт handshake |
| `connected` | сессия открыта |
| `error` | ошибка handshake / обрыв / blocked |

Поле `code` (при `error` или `not_activated`):

| `code` | HTTP / причина |
|---|---|
| `missing_credentials` | 401 `{"error":"Missing credentials"}` |
| `bad_device_id` | 400 `{"error":"Bad device ID"}` |
| `blocked` | 401 `{"error":"Blocked"}` или blocked в JSON по сокету |
| `internal_server_error` | 500 |
| `io_error` | сеть, timeout, прочее |
| `closed` | сервер закрыл WS (Close frame / EOF) |
| `""` | нет ошибки |

---

## 3. FFI (после `flutter_rust_bridge_codegen`)

Добавлены функции в `src/flutter_ffi.rs`:

```rust
main_get_fbp_ws_status() -> SyncReturn<String>   // JSON FbpWsStatus
main_send_fbp_ws_message(message: String) -> SyncReturn<bool>
```

### Чтение статуса (polling)

```dart
import 'dart:convert';
import 'package:flutter_hbb/models/platform_model.dart';

Map<String, dynamic> readWsStatus() {
  final raw = bind.mainGetFbpWsStatus(); // SyncReturn → String без await
  return jsonDecode(raw) as Map<String, dynamic>;
}

// Пример:
// {
//   "status": "connected",
//   "code": "",
//   "detail": "connected",
//   "connected_since": 1717654321
// }
```

### События (push, рекомендуется)

В `main.dart` → `_registerEventHandler()`:

```dart
platformFFI.registerEventHandler('fbp_ws_status', 'fbp_ws_status', (evt) async {
  final status = evt['status'] ?? '';
  final code = evt['code'] ?? '';
  final detail = evt['detail'] ?? '';
  // обновить Rx / StateGlobal:
  // not_activated | connecting | connected | error
});
```

Формат события:

```json
{
  "name": "fbp_ws_status",
  "status": "error",
  "code": "blocked",
  "detail": "{\"error\":\"Blocked\"}"
}
```

### Отправка сообщения на сервер

```dart
final ok = bind.mainSendFbpWsMessage(
  message: jsonEncode({'type': 'hello', 'foo': 'bar'}),
);
if (!ok) {
  // WS не в состоянии connected
}
```

---

## 4. Как дополнять логику read / write (Rust)

### Входящие сообщения (read)

Редактируйте **`handle_incoming_message`** в `fbp_ws.rs`:

```rust
pub fn handle_incoming_message(value: &Value) -> Option<String> {
    match value.get("type").and_then(|v| v.as_str()) {
        Some("ping") => Some(r#"{"type":"pong"}"#.to_string()),
        Some("your_command") => {
            // разобрать value, вернуть ответ
            Some(json!({"type": "your_reply"}).to_string())
        }
        _ => None, // молчим
    }
}
```

- Вызывается для **каждого текстового** WS-кадра.
- Возврат `Some(json)` → автоматически отправится на сервер.
- Возврат `None` → ничего не отправляем.
- Если в JSON есть `"error":"Blocked"` — сессия завершается, статус `error` / `blocked`.

### Исходящие при подключении

Редактируйте **`on_connected`**:

```rust
pub fn on_connected() -> Vec<String> {
    vec![
        json!({"type": "hello", "version": crate::VERSION}).to_string(),
    ]
}
```

### Исходящие из Flutter / другого Rust-кода

`send_message()` / FFI `main_send_fbp_ws_message` — очередь в активную сессию.

### Исходящие из Rust по таймеру / событию

Внутри `fbp_ws.rs` можно вызвать `send_message(&text)?` из любого кода **пока** `connected` (канал открыт).

---

## 5. Пересборка

```bash
# 1. Rust
cargo build --features flutter

# 2. Обновить bridge
cd flutter
flutter_rust_bridge_codegen \
  --rust-input ../src/flutter_ffi.rs \
  --dart-output ./lib/generated_bridge.dart \
  --c-output ./macos/Runner/bridge_generated.h
```

Новые методы во Flutter: `mainGetFbpWsStatus`, `mainSendFbpWsMessage` (имена уточните в `generated_bridge.dart` после codegen).
