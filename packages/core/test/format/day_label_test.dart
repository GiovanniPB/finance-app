import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('formatDayLabel', () {
    final today = DateTime(2026, 7, 27);

    test('hoje e ontem viram palavra', () {
      expect(formatDayLabel(today, today: today), 'Hoje');
      expect(formatDayLabel(DateTime(2026, 7, 26), today: today), 'Ontem');
    });

    test('datas mais antigas usam dia e mês em pt-BR', () {
      expect(
        formatDayLabel(DateTime(2026, 7, 23), today: today),
        '23 de julho',
      );
      expect(formatDayLabel(DateTime(2026, 3, 5), today: today), '5 de março');
    });

    test('ignora a hora ao comparar', () {
      expect(
        formatDayLabel(DateTime(2026, 7, 27, 23, 59), today: today),
        'Hoje',
      );
    });

    test('data futura não vira "Ontem"', () {
      expect(
        formatDayLabel(DateTime(2026, 7, 28), today: today),
        '28 de julho',
      );
    });

    test('atravessa a virada de ano sem confundir dia', () {
      expect(
        formatDayLabel(DateTime(2025, 12, 31), today: DateTime(2026)),
        'Ontem',
      );
    });
  });
}
