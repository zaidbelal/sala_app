import 'package:flutter_test/flutter_test.dart';
import 'package:sala/features/auth/login/services/auth_service.dart';

void main() {
  group('AuthService.formatPhone', () {
    test('normalizes local Yemeni numbers', () {
      expect(AuthService.formatPhone('777123456'), '+967777123456');
      expect(AuthService.formatPhone('0777123456'), '+967777123456');
    });

    test('normalizes Arabic digits and international numbers', () {
      expect(AuthService.formatPhone('٠٧٧٧١٢٣٤٥٦'), '+967777123456');
      expect(AuthService.formatPhone('967777123456'), '+967777123456');
    });

    test('rejects invalid numbers', () {
      expect(() => AuthService.formatPhone('12345'), throwsFormatException);
    });
  });
}
