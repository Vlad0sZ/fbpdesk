import 'dart:convert';

import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';

/// Read WS status from Rust (local or via IPC to `--server`) and update [stateGlobal].
void refreshWsStatusFromRust() {
  try {
    final status =
        jsonDecode(bind.mainGetFbpWsStatus()) as Map<String, dynamic>;
    final statusStr = status['status'] as String? ?? '';
    final code = status['code'] as String? ?? '';
    stateGlobal.wsStatus.value = parseWsStatus(statusStr, code);
  } catch (_) {
    stateGlobal.wsStatus.value = WsStatus.error;
  }
}

WsStatus parseWsStatus(String statusStr, String code) {
  switch (statusStr) {
    case 'not_activated':
      return WsStatus.notActivated;
    case 'connecting':
      return WsStatus.connecting;
    case 'connected':
      return WsStatus.connected;
    case 'error':
      return code == 'blocked' ? WsStatus.blocked : WsStatus.error;
    default:
      return statusStr.isEmpty ? WsStatus.notActivated : WsStatus.error;
  }
}
