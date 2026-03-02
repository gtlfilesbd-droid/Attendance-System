import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Phase 8: Encrypt/decrypt offline location queue at rest.
/// Key is stored in secure storage; AES-256-CBC with random IV per encryption.
const String _keyStorageKey = 'offline_queue_encryption_key';
const int _keyLength = 32;
const int _ivLength = 16;

class OfflineQueueCrypto {
  static const AndroidOptions _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
  static const FlutterSecureStorage _storage = FlutterSecureStorage(aOptions: _androidOptions);

  static Uint8List? _cachedKey;

  /// Get or create 32-byte key in secure storage.
  /// Key is cached only after successful read or write so restart does not lose decrypt ability.
  static Future<Uint8List> _getKey() async {
    if (_cachedKey != null) return _cachedKey!;
    String? keyBase64 = await _storage.read(key: _keyStorageKey);
    if (keyBase64 != null && keyBase64.isNotEmpty) {
      final decoded = base64.decode(keyBase64);
      if (decoded.length == _keyLength) {
        _cachedKey = Uint8List.fromList(decoded);
        return _cachedKey!;
      }
    }
    final key = enc.Key.fromSecureRandom(_keyLength);
    final keyList = Uint8List.fromList(key.bytes);
    await _storage.write(key: _keyStorageKey, value: base64.encode(keyList));
    _cachedKey = keyList;
    return _cachedKey!;
  }

  /// Encrypt plain UTF-8 string. Returns base64(IV + ciphertext) for storage.
  static Future<String> encrypt(String plain) async {
    final keyBytes = await _getKey();
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(_ivLength);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plain, iv: iv);
    final combined = Uint8List(_ivLength + encrypted.bytes.length)
      ..setRange(0, _ivLength, iv.bytes)
      ..setRange(_ivLength, _ivLength + encrypted.bytes.length, encrypted.bytes);
    return base64.encode(combined);
  }

  /// Decrypt string produced by [encrypt]. Returns plain UTF-8 string.
  /// [cipherBase64] can be legacy plain text; returns null if decryption fails (caller can treat as plain).
  static Future<String?> decrypt(String cipherBase64) async {
    try {
      final combined = base64.decode(cipherBase64);
      if (combined.length <= _ivLength) return null;
      final keyBytes = await _getKey();
      final key = enc.Key(keyBytes);
      final iv = enc.IV(Uint8List.sublistView(combined, 0, _ivLength));
      final cipherBytes = Uint8List.sublistView(combined, _ivLength, combined.length);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = enc.Encrypted(cipherBytes);
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (_) {
      return null;
    }
  }

  /// Decrypt list of stored strings. Items that fail to decrypt are returned as-is (legacy plain).
  static Future<List<String>> decryptList(List<String> stored) async {
    final out = <String>[];
    for (final s in stored) {
      if (s.isEmpty) continue;
      final dec = await decrypt(s);
      out.add(dec ?? s);
    }
    return out;
  }

  /// Encrypt list of plain JSON strings for storage.
  static Future<List<String>> encryptList(List<String> plainList) async {
    final out = <String>[];
    for (final s in plainList) {
      out.add(await encrypt(s));
    }
    return out;
  }
}
