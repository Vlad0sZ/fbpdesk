import 'package:flutter_hbb/models/platform_model.dart';

/// Current temporary password for activation API / backend sync.
/// Refreshes once if the server has not generated a password yet.
Future<String> getTemporaryPassword() async {
  var password = await bind.mainGetTemporaryPassword();
  if (password.isEmpty) {
    await bind.mainUpdateTemporaryPassword();
    password = await bind.mainGetTemporaryPassword();
  }
  if (password.isEmpty) {
    throw StateError('Temporary password is not available');
  }
  return password;
}
