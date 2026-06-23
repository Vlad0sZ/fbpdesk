import 'package:flutter_hbb/models/platform_model.dart';

/// Configuration keys for custom client
class CustomConfig {
  // Activation API endpoint
  static const String kActivationApiUrl = 'custom_activation_api_url';
  static const String kWebsocketUrl = 'custom_websocket_url';

  // Default values
  static const String defaultActivationApiUrl = 'https://api.fbpdesk.ru';
  static const String defaultWebsocketUrl = 'wss://api.fbpdesk.ru/ws';

  /// Get activation API URL from config or return default
  static String getActivationApiUrl() {
    final url = bind.mainGetLocalOption(key: kActivationApiUrl);
    return url.isEmpty ? defaultActivationApiUrl : url;
  }

  /// Set activation API URL
  static Future<void> setActivationApiUrl(String url) async {
    await bind.mainSetLocalOption(key: kActivationApiUrl, value: url);
  }

  static String getWebsocketUrl() {
    final url = bind.mainGetLocalOption(key: kWebsocketUrl);
    return url.isEmpty ? defaultWebsocketUrl : url;
  }

  static Future<void> setWebsocketUrl(String url) async {
    await bind.mainSetLocalOption(key: kWebsocketUrl, value: url);
  }
}
