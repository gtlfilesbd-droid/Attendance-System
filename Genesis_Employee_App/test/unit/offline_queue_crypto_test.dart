import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/services/offline_queue_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineQueueCrypto (Phase 8)', () {
    test('decrypt of plain text returns null so caller can treat as legacy', () async {
      // Plain JSON or non-base64 string: decryption fails, returns null.
      final result = await OfflineQueueCrypto.decrypt('{"latitude": 23.5, "longitude": 90.4}');
      expect(result, isNull);
    });

    test('decrypt of invalid base64 returns null', () async {
      final result = await OfflineQueueCrypto.decrypt('not-valid-base64!!!');
      expect(result, isNull);
    });

    test('decryptList passes through legacy plain when decrypt fails', () async {
      final stored = ['plain-json-item', '{"lat": 1}'];
      final out = await OfflineQueueCrypto.decryptList(stored);
      expect(out, orderedEquals(stored));
    });

    test('encrypt then decrypt returns same string', () async {
      const plain = '{"latitude": 23.5, "longitude": 90.4, "timestamp": "2024-01-15T10:00:00Z"}';
      final encrypted = await OfflineQueueCrypto.encrypt(plain);
      expect(encrypted, isNotEmpty);
      expect(encrypted, isNot(equals(plain)));
      final decrypted = await OfflineQueueCrypto.decrypt(encrypted);
      expect(decrypted, equals(plain));
    }, skip: 'Requires Flutter secure storage plugin (run on device/emulator)');

    test('encryptList then decryptList round-trips', () async {
      final plainList = [
        '{"latitude": 1.0, "longitude": 2.0}',
        '{"latitude": 3.0, "longitude": 4.0}',
      ];
      final encrypted = await OfflineQueueCrypto.encryptList(plainList);
      expect(encrypted.length, equals(2));
      final decrypted = await OfflineQueueCrypto.decryptList(encrypted);
      expect(decrypted, orderedEquals(plainList));
    }, skip: 'Requires Flutter secure storage plugin (run on device/emulator)');
  });
}
