import 'package:flutter/material.dart';
import 'package:flutter_hbb/custom/config.dart';
import 'package:get/get.dart';

/// Settings widget for custom client configuration
class CustomSettingsWidget extends StatefulWidget {
  final Future<void> Function(String value) setValue;
  final String Function() getValue;
  final String Function() getDefaultValue;
  final String title;

  const CustomSettingsWidget({
    Key? key,
    required this.title,
    required this.setValue,
    required this.getValue,
    required this.getDefaultValue,
  }) : super(key: key);

  @override
  State<CustomSettingsWidget> createState() => _CustomSettingsWidgetState();
}

class _CustomSettingsWidgetState extends State<CustomSettingsWidget> {
  final _apiUrlController = TextEditingController();
  final _isSaving = false.obs;
  final _successMessage = ''.obs;

  @override
  void initState() {
    super.initState();
    _loadCurrentUrl();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  void _loadCurrentUrl() {
    _apiUrlController.text = widget.getValue();
  }

  Future<void> _saveUrl() async {
    final url = _apiUrlController.text.trim();
    if (url.isEmpty) {
      return;
    }

    _isSaving.value = true;
    _successMessage.value = '';

    try {
      await widget.setValue(url);
      _successMessage.value = 'Saved successfully';

      // Clear success message after 2 seconds
      Future.delayed(Duration(seconds: 2), () {
        _successMessage.value = '';
      });
    } catch (e) {
      _successMessage.value = 'Failed to save: $e';
    } finally {
      _isSaving.value = false;
    }
  }

  Future<void> _resetToDefault() async {
    _apiUrlController.text = widget.getDefaultValue();
    await _saveUrl();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _apiUrlController,
                decoration: InputDecoration(
                  hintText: 'https://api.example.com',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                enabled: !_isSaving.value,
              ),
            ),
            SizedBox(width: 8),
            Obx(() => ElevatedButton(
                  onPressed: _isSaving.value ? null : _saveUrl,
                  child: _isSaving.value
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Save'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                )),
            SizedBox(width: 8),
            TextButton(
              onPressed: _resetToDefault,
              child: Text('Reset'),
            ),
          ],
        ),
        Obx(() => _successMessage.value.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _successMessage.value,
                  style: TextStyle(
                    color: _successMessage.value.contains('Failed')
                        ? Colors.red
                        : Colors.green,
                    fontSize: 13,
                  ),
                ),
              )
            : SizedBox.shrink()),
        SizedBox(height: 8),
      ],
    );
  }
}
