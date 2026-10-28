import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class Credentials {
  static const _iterations = 60000;
  static String now() => DateTime.now().toUtc().toIso8601String();

  static String randomToken(int bytes) {
    final random = Random.secure();
    return base64UrlEncode(List.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  static String sha(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  /// PBKDF2-HMAC-SHA256 (비밀번호를 되돌릴 수 없는 값으로)
  static String hashPassword(String password, String salt) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = Uint8List.fromList([...utf8.encode(salt), 0, 0, 0, 1]);
    var u = hmac.convert(block).bytes;
    final result = List<int>.of(u);
    for (var i = 1; i < _iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Encode(result);
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
