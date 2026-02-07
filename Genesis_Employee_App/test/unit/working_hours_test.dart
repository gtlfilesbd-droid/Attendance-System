import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/utils/working_hours.dart';

void main() {
  group('Working hours (time limit disabled)', () {
    test('isWorkingHours returns true for all times when duty is active', () {
      // Time limit disabled: tracking runs between Start duty and End duty only
      expect(isWorkingHours(DateTime(2025, 2, 2, 12, 0)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 10, 0)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 18, 0)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 9, 31)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 9, 30)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 9, 0)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 8, 30)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 0, 0)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 18, 30)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 19, 0)), isTrue);
      expect(isWorkingHours(DateTime(2025, 2, 2, 23, 59)), isTrue);
    });
  });
}
