import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/custom/activation_state.dart';
import 'package:flutter_hbb/custom/password_gen.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/custom/config.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:get/get.dart';

class DeviceActivationPage extends StatefulWidget {
  const DeviceActivationPage({Key? key}) : super(key: key);

  @override
  State<DeviceActivationPage> createState() => _DeviceActivationPageState();
}

class _DeviceActivationPageState extends State<DeviceActivationPage> {
  final _activationCodeController = TextEditingController();
  final _isLoading = false.obs;
  final _errorMessage = ''.obs;
  DeviceActivationState get _activation => DeviceActivationState.find;

  @override
  void initState() {
    super.initState();
    _activation.reload();
  }

  @override
  void dispose() {
    _activationCodeController.dispose();
    super.dispose();
  }

  /// Submit activation code to backend and save token
  Future<void> _submitActivationCode() async {
    final code = _activationCodeController.text.trim();
    if (code.isEmpty) {
      _errorMessage.value = translate("activation_enter_empty_error");
      return;
    }

    _isLoading.value = true;
    _errorMessage.value = '';

    try {
      // Get API URL from config
      final apiUrl = CustomConfig.getActivationApiUrl();
      final rustDeskId = await bind.mainGetMyId();
      final osInfo = bind.mainGetSysinfo();
      final mac = bind.mainGetMac();
      final basic = jsonDecode(bind.mainGetLoginDeviceInfo());
      final password = await ensurePermanentPassword();

      final response = await http.post(
        Uri.parse('$apiUrl/api/activate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'hostname': basic['name'],
          'macAddress': mac,
          'rustdeskId': rustDeskId,
          'rustdeskPassword': password,
          'osinfo': osInfo
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        final deviceId = data['deviceId'];

        await _activation.save(deviceId: deviceId, token: token);
        _activationCodeController.clear();
      } else {
        _errorMessage.value = 'Invalid activation code';
      }
    } catch (e) {
      _errorMessage.value = translate("activation_enter_error") + e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  /// Deactivate device by removing token
  // Future<void> _deactivateDevice() async {
  //   // TODO: Optionally notify backend about deactivation
  //   await bind.mainSetLocalOption(
  //     key: kCommConfKeyDeviceState,
  //     value: '',
  //   );
  //   _isActivated.value = false;
  // }

  @override
  Widget build(BuildContext context) {
    return Obx(() => _activation.isActivated.value
        ? _buildActivatedView(context)
        : _activation.isBlocked.value
            ? _buildBlockedView(context)
            : _buildActivationForm(context));
  }

  Widget _buildBlockedView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.fromARGB(255, 248, 81, 31).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Color.fromARGB(255, 248, 81, 31),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Color.fromARGB(255, 248, 81, 31),
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                translate('activation_device_blocked_title'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          // ElevatedButton(
          //   onPressed: _deactivateDevice,
          //   style: ElevatedButton.styleFrom(
          //     backgroundColor: Colors.red,
          //     foregroundColor: Colors.white,
          //   ),
          //   child: Text('Deactivate Device'),
          // ),
        ],
      ),
    );
  }

  /// View shown when device is activated
  Widget _buildActivatedView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.fromARGB(255, 50, 190, 166).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Color.fromARGB(255, 50, 190, 166),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Color.fromARGB(255, 50, 190, 166),
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                translate('activation_device_activated_title'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            '${translate('activation_device_id')}${_activation.deviceId.value}',
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(height: 16),
          // ElevatedButton(
          //   onPressed: _deactivateDevice,
          //   style: ElevatedButton.styleFrom(
          //     backgroundColor: Colors.red,
          //     foregroundColor: Colors.white,
          //   ),
          //   child: Text('Deactivate Device'),
          // ),
        ],
      ),
    );
  }

  /// Form for entering activation code
  Widget _buildActivationForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translate('activation_enter_title'),
          style: TextStyle(fontSize: 14),
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _activationCodeController,
                decoration: InputDecoration(
                  hintText: translate('activation_enter_placeholder'),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                enabled: !_isLoading.value,
                onSubmitted: (_) => _submitActivationCode(),
              ),
            ),
            SizedBox(width: 12),
            Obx(() => ElevatedButton(
                  onPressed: _isLoading.value ? null : _submitActivationCode,
                  child: _isLoading.value
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(translate('activation_enter_button')),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                )),
          ],
        ),
        Obx(() => _errorMessage.value.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage.value,
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              )
            : SizedBox.shrink()),
      ],
    );
  }
}
