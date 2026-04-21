import 'package:flutter_hbb/common.dart';

/// Configuration keys for custom client
class CustomConfig {
  // Activation API endpoint
  static const String kActivationApiUrl = 'custom_activation_api_url';

  // Default values
  static const String defaultActivationApiUrl = 'https://api.example.com';

  /// Get activation API URL from config or return default
  static String getActivationApiUrl() {
    final url = bind.mainGetLocalOption(key: kActivationApiUrl);
    return url.isEmpty ? defaultActivationApiUrl : url;
  }

  /// Set activation API URL
  static Future<void> setActivationApiUrl(String url) async {
    await bind.mainSetLocalOption(key: kActivationApiUrl, value: url);
  }
}
