import 'dart:math';

import 'package:flutter_hbb/models/platform_model.dart';

Future<String> ensurePermanentPassword() async {
  final password = _generatePassword();
  final ok = await bind.mainSetPermanentPasswordWithResult(password: password);
  if (!ok) throw StateError('Failed to set permanent password');
  return password;
}

String _generatePassword() {
  const numbers = '1234567890';
  const lowerChars = 'abcdefghijkmnopqrstuvwxyz';
  const upperChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const list = [numbers, lowerChars, upperChars];

  final rand = Random.secure();

  // строчный + заглавные + цифры -> больше 8 символов
  return List.generate(12, (index) {
    final l = list[(index + rand.nextInt(100)) % list.length];
    return l[rand.nextInt(l.length)];
  }).join();
}
