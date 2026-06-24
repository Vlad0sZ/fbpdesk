// flutter/lib/custom/activation_state.dart
import 'dart:async';

import 'package:flutter_hbb/custom/ws_status.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';

const kCommConfKeyDeviceToken = 'device_activation_token';
const kCommConfKeyDeviceId = 'device_activation_device_id';

class DeviceActivationState extends GetxController {
  static DeviceActivationState get find =>
      Get.isRegistered<DeviceActivationState>()
          ? Get.find<DeviceActivationState>()
          : Get.put(DeviceActivationState(), permanent: true);

  final isActivated = false.obs;
  final isBlocked = false.obs;
  final deviceId = ''.obs;
  final token = ''.obs;

  /// Token and device id saved after successful API activation.
  bool get hasCredentials =>
      token.value.isNotEmpty && deviceId.value.isNotEmpty;

  /// Lock connection tab: blocked by server, or never activated (no credentials).
  bool get shouldLockConnection => isBlocked.value || !hasCredentials;

  Timer? _wsPollTimer;

  /// True when API activation is done and WS session is up (not blocked).
  /// UI: green "activated" card in settings.

  @override
  void onInit() {
    super.onInit();
    reload();
    ever(stateGlobal.wsStatus, (_) => _syncFromWsStatus());
    refreshWsStatusFromRust();
    _wsPollTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => refreshWsStatusFromRust());
  }

  @override
  void onClose() {
    _wsPollTimer?.cancel();
    super.onClose();
  }

  void reload() {
    token.value = bind.mainGetLocalOption(key: kCommConfKeyDeviceToken);
    deviceId.value = bind.mainGetLocalOption(key: kCommConfKeyDeviceId);
    _pushCredentialsToHostServer();
    _syncFromWsStatus();
  }

  /// Re-send saved credentials so the out-of-process `--server` can connect WS.
  Future<void> _pushCredentialsToHostServer() async {
    if (!hasCredentials) return;
    await bind.mainSetLocalOption(
        key: kCommConfKeyDeviceToken, value: token.value);
    await bind.mainSetLocalOption(
        key: kCommConfKeyDeviceId, value: deviceId.value);
  }

  void _syncFromWsStatus() {
    isBlocked.value = stateGlobal.wsStatus.value == WsStatus.blocked;
    isActivated.value = hasCredentials &&
        !isBlocked.value &&
        stateGlobal.wsStatus.value == WsStatus.connected;
  }

  Future<void> save({required String token, required String deviceId}) async {
    await bind.mainSetLocalOption(key: kCommConfKeyDeviceToken, value: token);
    await bind.mainSetLocalOption(key: kCommConfKeyDeviceId, value: deviceId);
    reload();
  }

  Future<void> clear() async {
    await save(token: '', deviceId: '');
  }
}
