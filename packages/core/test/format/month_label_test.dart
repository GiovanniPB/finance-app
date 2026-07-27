import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('monthLabel', () {
    test('mês corrente aparece sem o ano', () {
      expect(
        monthLabel(DateTime(2026, 7), today: DateTime(2026, 7, 27)),
        'julho',
      );
    });

    test('outro ano ganha o ano', () {
      expect(
        monthLabel(DateTime(2025, 3), today: DateTime(2026, 7, 27)),
        'março de 2025',
      );
    });

    test('ano seguinte também ganha o ano', () {
      expect(
        monthLabel(DateTime(2027), today: DateTime(2026, 7, 27)),
        'janeiro de 2027',
      );
    });

    test('cobre os doze meses', () {
      final today = DateTime(2026, 7, 27);
      final labels = [
        for (var m = 1; m <= 12; m++)
          monthLabel(DateTime(2026, m), today: today),
      ];

      expect(labels, hasLength(12));
      expect(labels.toSet(), hasLength(12));
      expect(labels.first, 'janeiro');
      expect(labels.last, 'dezembro');
    });
  });
}
