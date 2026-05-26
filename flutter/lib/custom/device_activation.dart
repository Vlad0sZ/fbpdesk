import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/custom/config.dart';
import 'package:get/get.dart';

const kCommConfKeyDeviceState = 'device_activation_token';

class DeviceActivationPage extends StatefulWidget {
  const DeviceActivationPage({Key? key}) : super(key: key);

  @override
  State<DeviceActivationPage> createState() => _DeviceActivationPageState();
}

class _DeviceActivationPageState extends State<DeviceActivationPage> {
  final _activationCodeController = TextEditingController();
  final _isActivated = false.obs;
  final _isLoading = false.obs;
  final _errorMessage = ''.obs;

  @override
  void initState() {
    super.initState();
    _checkActivationStatus();
  }

  @override
  void dispose() {
    _activationCodeController.dispose();
    super.dispose();
  }

  /// Check if device is already activated by reading token from local config
  void _checkActivationStatus() {
    final token = bind.mainGetLocalOption(key: kCommConfKeyDeviceState);
    _isActivated.value = token.isNotEmpty;
  }

  /// Submit activation code to backend and save token
  Future<void> _submitActivationCode() async {
    final code = _activationCodeController.text.trim();
    if (code.isEmpty) {
      _errorMessage.value = 'Please enter activation code';
      return;
    }

    _isLoading.value = true;
    _errorMessage.value = '';

    try {
      // Get API URL from config
      final apiUrl = CustomConfig.getActivationApiUrl();
      final deviceId = bind.mainGetMyId();

      // TODO: Uncomment when backend is ready
      // final response = await http.post(
      //   Uri.parse('$apiUrl/api/activate'),
      //   headers: {'Content-Type': 'application/json'},
      //   body: jsonEncode({'code': code, 'device_id': deviceId}),
      // );
      //
      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body);
      //   final token = data['token'];
      //   await bind.mainSetLocalOption(
      //     key: kCommConfKeyDeviceState,
      //     value: token,
      //   );
      //   _isActivated.value = true;
      //   _activationCodeController.clear();
      // } else {
      //   _errorMessage.value = 'Invalid activation code';
      // }

      // Mock activation for testing (remove in production)
      debugPrint('Activation API URL: $apiUrl');
      debugPrint('Device ID: $deviceId');
      debugPrint('Activation code: $code');

      await Future.delayed(Duration(seconds: 1));
      final mockToken = 'token_$code';

      await bind.mainSetLocalOption(
        key: kCommConfKeyDeviceState,
        value: mockToken,
      );

      _isActivated.value = true;
      _activationCodeController.clear();
    } catch (e) {
      _errorMessage.value = 'Activation failed: $e';
    } finally {
      _isLoading.value = false;
    }
  }

  /// Deactivate device by removing token
  Future<void> _deactivateDevice() async {
    // TODO: Optionally notify backend about deactivation
    await bind.mainSetLocalOption(
      key: kCommConfKeyDeviceState,
      value: '',
    );
    _isActivated.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => _isActivated.value
        ? _buildActivatedView(context)
        : _buildActivationForm(context));
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
                'Device is activated',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Device ID: ${bind.mainGetMyId()}',
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _deactivateDevice,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Deactivate Device'),
          ),
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
          'Enter activation code to link this device',
          style: TextStyle(fontSize: 14),
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _activationCodeController,
                decoration: InputDecoration(
                  hintText: 'Activation code',
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
                      : Text('Activate'),
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
