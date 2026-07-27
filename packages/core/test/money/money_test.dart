import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Money — construção', () {
    test('fromMinor guarda centavos e moeda padrão BRL', () {
      const money = Money.fromMinor(1050);
      expect(money.amountMinor, 1050);
      expect(money.currency, 'BRL');
    });

    test('fromMajor arredonda reais para centavos', () {
      expect(Money.fromMajor(10.5).amountMinor, 1050);
      expect(Money.fromMajor(10.555).amountMinor, 1056);
      expect(Money.fromMajor(0.1 + 0.2).amountMinor, 30); // sem drift de float
    });

    test('zero é 0 na moeda informada', () {
      const zero = Money.zero(currency: 'USD');
      expect(zero.isZero, isTrue);
      expect(zero.currency, 'USD');
    });
  });

  group('Money — aritmética', () {
    test('soma e subtração operam em centavos', () {
      expect(
        const Money.fromMinor(1000) + const Money.fromMinor(250),
        const Money.fromMinor(1250),
      );
      expect(
        const Money.fromMinor(1000) - const Money.fromMinor(250),
        const Money.fromMinor(750),
      );
    });

    test('negação e valor absoluto', () {
      expect(-const Money.fromMinor(500), const Money.fromMinor(-500));
      expect(const Money.fromMinor(-500).abs, const Money.fromMinor(500));
    });

    test('multiplicação por escalar inteiro', () {
      expect(const Money.fromMinor(333) * 3, const Money.fromMinor(999));
    });

    test('operações entre moedas diferentes lançam', () {
      expect(
        () =>
            const Money.fromMinor(100) +
            const Money.fromMinor(100, currency: 'USD'),
        throwsArgumentError,
      );
    });
  });

  group('Money — comparação', () {
    test('operadores relacionais', () {
      expect(const Money.fromMinor(100) < const Money.fromMinor(200), isTrue);
      expect(const Money.fromMinor(200) >= const Money.fromMinor(200), isTrue);
    });

    test('isNegative / isPositive / isZero', () {
      expect(const Money.fromMinor(-1).isNegative, isTrue);
      expect(const Money.fromMinor(1).isPositive, isTrue);
      expect(const Money.zero().isZero, isTrue);
    });
  });

  group('Money — allocate/split (sem perder centavos)', () {
    test('split igualitário distribui o resto de forma determinística', () {
      final parts = const Money.fromMinor(1000).split(3);
      expect(parts.map((m) => m.amountMinor), [334, 333, 333]);
      expect(_sum(parts), const Money.fromMinor(1000));
    });

    test('allocate proporcional fecha a soma exata', () {
      final parts = const Money.fromMinor(1000).allocate([1, 1, 1, 1, 1, 1, 1]);
      expect(_sum(parts), const Money.fromMinor(1000));
      expect(parts.length, 7);
    });

    test('allocate por cotas desiguais', () {
      final parts = const Money.fromMinor(1000).allocate([2, 1, 1]);
      expect(_sum(parts), const Money.fromMinor(1000));
      expect(
        parts.first.amountMinor,
        greaterThanOrEqualTo(parts[1].amountMinor),
      );
    });

    test('allocate de valor negativo (dívida) ainda fecha', () {
      final parts = const Money.fromMinor(-1000).split(3);
      expect(_sum(parts), const Money.fromMinor(-1000));
    });

    test('split inválido lança', () {
      expect(() => const Money.fromMinor(100).split(0), throwsArgumentError);
      expect(
        () => const Money.fromMinor(100).allocate([]),
        throwsArgumentError,
      );
      expect(
        () => const Money.fromMinor(100).allocate([0, 0]),
        throwsArgumentError,
      );
    });
  });

  group('Money — formatação e igualdade', () {
    test('formata no padrão pt-BR', () {
      expect(const Money.fromMinor(123456).format(), r'R$ 1.234,56');
      expect(const Money.fromMinor(-1000).format(), r'-R$ 10,00');
      expect(const Money.fromMinor(5).format(), r'R$ 0,05');
      expect(const Money.fromMinor(100000000).format(), r'R$ 1.000.000,00');
    });

    test('omite o símbolo quando withSymbol é false', () {
      const money = Money.fromMinor(123456);
      expect(money.format(withSymbol: false), '1.234,56');
      expect(
        const Money.fromMinor(-1000).format(withSymbol: false),
        '-10,00',
      );
      expect(const Money.fromMinor(5).format(withSymbol: false), '0,05');
    });

    test('withSymbol não altera o agrupamento nem o sinal', () {
      const money = Money.fromMinor(-100000000);
      expect(money.format(), r'-R$ 1.000.000,00');
      expect(money.format(withSymbol: false), '-1.000.000,00');
    });

    test('usa o código quando a moeda não tem símbolo conhecido', () {
      const money = Money.fromMinor(1000, currency: 'JPY');
      expect(money.format(), 'JPY 10,00');
      expect(money.format(withSymbol: false), '10,00');
    });

    test('igualdade por valor considera moeda', () {
      expect(const Money.fromMinor(100), const Money.fromMinor(100));
      expect(
        const Money.fromMinor(100),
        isNot(const Money.fromMinor(100, currency: 'USD')),
      );
      expect(
        const Money.fromMinor(100).hashCode,
        const Money.fromMinor(100).hashCode,
      );
    });
  });
}

Money _sum(List<Money> parts) =>
    parts.fold(const Money.zero(), (acc, m) => acc + m);
