import 'dart:math';

import 'package:flutter_hbb/models/platform_model.dart';

Future<String> ensurePermanentPassword() async {
  final password = _generatePassword();
  final ok = await bind.mainSetPermanentPasswordWithResult(password: password);
  if (!ok) throw StateError('Failed to set permanent password');
  return password;
}

String _generatePassword() {
  const chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rand = Random.secure();
  return List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
}
