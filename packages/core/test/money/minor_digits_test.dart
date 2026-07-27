import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('MinorDigits.append', () {
    test('o primeiro dígito vira centavo', () {
      expect(MinorDigits.append(0, 1), 1);
    });

    test('cada dígito empurra os anteriores para a esquerda', () {
      var value = 0;
      for (final digit in [1, 4, 2]) {
        value = MinorDigits.append(value, digit);
      }

      expect(value, 142);
      expect(Money.fromMinor(value).format(withSymbol: false), '1,42');
    });

    test('zero à esquerda não conta como dígito', () {
      expect(MinorDigits.append(0, 0), 0);
      expect(MinorDigits.append(MinorDigits.append(0, 0), 5), 5);
    });

    test('para de aceitar no décimo dígito', () {
      const noLimite = 9999999999; // 99.999.999,99

      expect(MinorDigits.append(noLimite, 9), noLimite);
    });

    test('aceita até o décimo dígito', () {
      const noveDigitos = 999999999;

      expect(MinorDigits.append(noveDigitos, 9), 9999999999);
    });

    test('rejeita o que não é dígito', () {
      expect(() => MinorDigits.append(0, 10), throwsArgumentError);
      expect(() => MinorDigits.append(0, -1), throwsArgumentError);
    });
  });

  group('MinorDigits.removeLast', () {
    test('apaga o dígito da direita', () {
      expect(MinorDigits.removeLast(142), 14);
    });

    test('zero permanece zero', () {
      expect(MinorDigits.removeLast(0), 0);
    });

    test('apagar o último dígito zera', () {
      expect(MinorDigits.removeLast(7), 0);
    });
  });
}
