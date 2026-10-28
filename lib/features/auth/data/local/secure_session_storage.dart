import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/authenticated_user.dart';

class SecureSessionStorage {
  SecureSessionStorage(this.storage);
  final FlutterSecureStorage storage;
  static const _session = 'lifeline_session';
  static const _salt = 'lifeline_unlock_salt';
  static const _verifier = 'lifeline_unlock_verifier';

  Future<void> save(AuthenticatedUser user, String password) async {
    final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await storage.write(key: _salt, value: base64Encode(salt));
    await storage.write(
      key: _verifier,
      value: base64Encode(
        await Isolate.run(() => deriveUnlockKey(password, salt)),
      ),
    );
    await storage.write(key: _session, value: jsonEncode(user.toJson()));
  }

  Future<bool> verify(String password) async {
    final salt = await storage.read(key: _salt);
    final expected = await storage.read(key: _verifier);
    if (salt == null || expected == null) return false;
    final saltBytes = base64Decode(salt);
    final actual = await Isolate.run(
      () => deriveUnlockKey(password, saltBytes),
    );
    final bytes = base64Decode(expected);
    if (actual.length != bytes.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual[i] ^ bytes[i];
    }
    return difference == 0;
  }

  Future<AuthenticatedUser?> read() async {
    final raw = await storage.read(key: _session);
    if (raw == null) return null;
    try {
      return AuthenticatedUser.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    await storage.delete(key: _session);
    await storage.delete(key: _salt);
    await storage.delete(key: _verifier);
  }
}

List<int> deriveUnlockKey(String password, List<int> salt) {
  final key = utf8.encode(password);
  final hmac = Hmac(sha256, key);
  final block = [...salt, 0, 0, 0, 1];
  var value = hmac.convert(block).bytes;
  final result = List<int>.from(value);
  for (var i = 1; i < 120000; i++) {
    value = hmac.convert(value).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= value[j];
    }
  }
  return result;
}
