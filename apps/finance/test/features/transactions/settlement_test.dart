import 'package:core/core.dart';
import 'package:finance/features/transactions/domain/settlement.dart';
import 'package:flutter_test/flutter_test.dart';

/// O algoritmo guloso de acerto, e os três estados que chegam à tela vazios.
///
/// Dart puro: nenhum destes casos precisa de banco, e é aqui que a matemática
/// do saldo se prova. O SQL que produz os saldos tem teste próprio, que executa
/// de verdade (`settlement_repository_impl_test.dart`).
void main() {
  MemberBalance balance(String userId, int minor, {String currency = 'BRL'}) =>
      MemberBalance(
        userId: userId,
        net: Money.fromMinor(minor, currency: currency),
      );

  /// A soma de tudo que sai de [userId] menos tudo que entra, em centavos.
  int movement(List<SettlementTransfer> transfers, String userId) =>
      transfers.fold(0, (sum, t) {
        if (t.fromUserId == userId) return sum + t.amount.amountMinor;
        if (t.toUserId == userId) return sum - t.amount.amountMinor;
        return sum;
      });

  group('minimalTransfers', () {
    test('sem saldo nenhum, não propõe transferência', () {
      expect(minimalTransfers(const []), isEmpty);
    });

    test('com todo mundo quite, não propõe transferência', () {
      final transfers = minimalTransfers([
        balance('ana', 0),
        balance('bruno', 0),
        balance('carla', 0),
      ]);

      expect(transfers, isEmpty);
    });

    test('um devedor e um credor viram uma transferência', () {
      final transfers = minimalTransfers([
        balance('ana', 8000),
        balance('bruno', -8000),
      ]);

      expect(transfers, hasLength(1));
      expect(transfers.single.fromUserId, 'bruno');
      expect(transfers.single.toUserId, 'ana');
      expect(transfers.single.amount, const Money.fromMinor(8000));
    });

    test('um pagou tudo entre três: duas transferências (n−1)', () {
      // Mercado de R$ 240 pago pela Ana, dividido em três: ela adiantou R$ 160.
      final transfers = minimalTransfers([
        balance('ana', 16000),
        balance('bruno', -8000),
        balance('carla', -8000),
      ]);

      expect(transfers, hasLength(2));
      expect(transfers.every((t) => t.toUserId == 'ana'), isTrue);
      expect(movement(transfers, 'ana'), -16000);
    });

    // O triângulo — A deve a B, B deve a C, C deve a A — **não** tem teste
    // próprio aqui, e isso é de propósito: quando os saldos chegam a esta
    // função ele já virou três zeros, indistinguível do caso "todo mundo
    // quite". O triângulo de verdade se prova onde a soma acontece, no
    // `settlement_repository_impl_test.dart`. Um teste aqui daria a sensação de
    // cobrir o caso sem exercitar nada.
    test('o centavo indivisível não evapora', () {
      // R$ 0,01 pago pelo Bruno e rateado com a Ana: pelo método do maior resto
      // a parte dela é 1 centavo e a dele 0, então ele adiantou um centavo.
      final transfers = minimalTransfers([
        balance('ana', -1),
        balance('bruno', 1),
      ]);

      expect(transfers, hasLength(1));
      expect(transfers.single.amount, const Money.fromMinor(1));
      expect(transfers.single.fromUserId, 'ana');
    });

    test('empate de valor tem ordem estável, não sorte do Map', () {
      // Dois credores com o mesmo valor: o desempate é por `userId`, então
      // 'ana' vem antes de 'bruno' — e vem sempre, não em 50% das rodadas.
      final ordered = minimalTransfers([
        balance('bruno', 5000),
        balance('ana', 5000),
        balance('carla', -10000),
      ]);
      final reversed = minimalTransfers([
        balance('ana', 5000),
        balance('bruno', 5000),
        balance('carla', -10000),
      ]);

      expect(ordered.map((t) => t.toUserId), ['ana', 'bruno']);
      expect(reversed.map((t) => t.toUserId), ['ana', 'bruno']);
    });

    test('cada transferência zera ao menos uma ponta', () {
      // Quatro pessoas, valores que não casam de primeira: o guloso ainda fica
      // em n−1 = 3, que é o limite que a decisão do ADR 0012 promete.
      final transfers = minimalTransfers([
        balance('ana', 10000),
        balance('bruno', 5000),
        balance('carla', -12000),
        balance('davi', -3000),
      ]);

      expect(transfers.length, lessThanOrEqualTo(3));
      expect(movement(transfers, 'ana'), -10000);
      expect(movement(transfers, 'bruno'), -5000);
      expect(movement(transfers, 'carla'), 12000);
      expect(movement(transfers, 'davi'), 3000);
    });

    // Invariante global de `docs/product.md`: agregado com moedas divergentes se
    // recusa a somar em vez de somar errado.
    test('com duas moedas, recusa propor', () {
      final transfers = minimalTransfers([
        balance('ana', 5000),
        balance('bruno', -5000, currency: 'USD'),
      ]);

      expect(transfers, isEmpty);
    });

    test('preserva a moeda do espaço na proposta', () {
      final transfers = minimalTransfers([
        balance('ana', 5000, currency: 'USD'),
        balance('bruno', -5000, currency: 'USD'),
      ]);

      expect(transfers.single.amount.currency, 'USD');
    });
  });

  group('Settlement', () {
    test('sem despesa dividida, é "nada dividido" e não "tudo quite"', () {
      expect(Settlement.nothingSplit.hasNothingSplit, isTrue);
      expect(Settlement.nothingSplit.isAllSettled, isFalse);
      expect(Settlement.nothingSplit.transfers, isEmpty);
    });

    test('com divisão que se cancela, é "tudo quite"', () {
      final settlement = Settlement.from(
        balances: [balance('ana', 0), balance('bruno', 0)],
        splitCount: 4,
      );

      expect(settlement.isAllSettled, isTrue);
      expect(settlement.hasNothingSplit, isFalse);
      expect(settlement.transfers, isEmpty);
    });

    test('com saldo, não é nem vazio nem quite', () {
      final settlement = Settlement.from(
        balances: [balance('ana', 8000), balance('bruno', -8000)],
        splitCount: 1,
      );

      expect(settlement.hasNothingSplit, isFalse);
      expect(settlement.isAllSettled, isFalse);
      expect(settlement.transfers, hasLength(1));
    });

    test('moeda divergente é um terceiro estado, não um vazio', () {
      final settlement = Settlement.from(
        balances: [
          balance('ana', 5000),
          balance('bruno', -5000, currency: 'USD'),
        ],
        splitCount: 2,
      );

      expect(settlement.isMixedCurrency, isTrue);
      expect(settlement.isAllSettled, isFalse);
      expect(settlement.hasNothingSplit, isFalse);
      expect(settlement.transfers, isEmpty);
    });

    test('a soma dos saldos tem de fechar em zero', () {
      // O `assert` protege contra defeito na leitura do banco — saldo que não
      // fecha significa lançamento contado uma vez e parte contada zero, e sem
      // esta rede a tela mostraria uma dívida inventada.
      expect(
        () => Settlement.from(
          balances: [balance('ana', 8000), balance('bruno', -3000)],
          splitCount: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('acha o saldo de uma pessoa, e devolve nulo para quem não rateou', () {
      final settlement = Settlement.from(
        balances: [balance('ana', 8000), balance('bruno', -8000)],
        splitCount: 1,
      );

      expect(settlement.balanceOf('ana')?.net, const Money.fromMinor(8000));
      expect(settlement.balanceOf('ana')?.isCreditor, isTrue);
      expect(settlement.balanceOf('bruno')?.isDebtor, isTrue);
      expect(settlement.balanceOf('carla'), isNull);
    });

    // Só quem está na linha pode registrar o acerto — é o que evita a pergunta
    // "quem tem direito de declarar pagamento alheio?".
    test('separa as transferências que envolvem quem está olhando', () {
      final settlement = Settlement.from(
        balances: [
          balance('ana', 10000),
          balance('bruno', -4000),
          balance('carla', -6000),
        ],
        splitCount: 3,
      );

      expect(settlement.transfersInvolving('ana'), hasLength(2));
      expect(settlement.transfersInvolving('bruno'), hasLength(1));
      expect(settlement.transfersInvolving('davi'), isEmpty);
    });
  });
}
