import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/services/background_worker.dart';

void main() {
  group('Notification display (BackgroundWorker)', () {
    test('notification channel ID is set', () {
      expect(
        BackgroundWorker.notificationChannelId,
        equals('genesis_tracking_channel'),
      );
    });

    test('notification ID is set', () {
      expect(BackgroundWorker.notificationId, equals(888));
    });

    test('startService does not throw', () async {
      final worker = BackgroundWorker();
      await expectLater(worker.startService(), completes);
    });

    test('stopService does not throw', () async {
      final worker = BackgroundWorker();
      await expectLater(worker.stopService(), completes);
    });
  });
}
