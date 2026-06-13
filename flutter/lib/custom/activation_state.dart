// flutter/lib/custom/activation_state.dart
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

  @override
  void onInit() {
    super.onInit();
    reload();
  }

  void reload() {
    token.value = bind.mainGetLocalOption(key: kCommConfKeyDeviceToken);
    deviceId.value = bind.mainGetLocalOption(key: kCommConfKeyDeviceId);
    isActivated.value = stateGlobal.wsStatus.value == WsStatus.connected;
    isBlocked.value = stateGlobal.wsStatus.value == WsStatus.blocked;
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
