import 'package:core/core.dart';
import 'package:finance/features/transactions/domain/expense_split.dart';
import 'package:flutter_test/flutter_test.dart';

/// A entidade da parte, e a soma que a tela usa para provar que o rateio fecha.
void main() {
  ExpenseSplit split({
    String id = 'split-1',
    String userId = 'user-1',
    int amountMinor = 12000,
  }) => ExpenseSplit(
    id: id,
    transactionId: 'tx-1',
    spaceId: 'space-1',
    userId: userId,
    amount: Money.fromMinor(amountMinor),
    createdAt: DateTime.utc(2026, 7, 28),
    updatedAt: DateTime.utc(2026, 7, 28),
  );

  group('fromRow', () {
    test('lê a linha do SQLite local', () {
      final parsed = ExpenseSplit.fromRow({
        'id': 'split-1',
        'transaction_id': 'tx-1',
        'space_id': 'space-1',
        'user_id': 'user-2',
        'amount_minor': 12000,
        'currency': 'BRL',
        'created_at': '2026-07-28T00:00:00.000Z',
        'updated_at': '2026-07-28T00:00:00.000Z',
      });

      expect(parsed.userId, 'user-2');
      expect(parsed.amount, const Money.fromMinor(12000));
    });

    // A parte é positiva mesmo sendo de uma despesa: ela responde "quanto disto
    // é seu", e a resposta é uma quantia. Se um dia uma linha chegar negativa —
    // de um estorno mal mapeado, por exemplo —, o módulo evita que a soma das
    // partes fique menor que o total sem ninguém notar.
    test('descarta o sinal de uma linha negativa', () {
      final parsed = ExpenseSplit.fromRow({
        'id': 'split-1',
        'transaction_id': 'tx-1',
        'space_id': 'space-1',
        'user_id': 'user-1',
        'amount_minor': -500,
        'currency': 'BRL',
        'created_at': '2026-07-28T00:00:00.000Z',
        'updated_at': '2026-07-28T00:00:00.000Z',
      });

      expect(parsed.amount, const Money.fromMinor(500));
    });

    test('parte de zero é válida', () {
      final parsed = ExpenseSplit.fromRow({
        'id': 'split-1',
        'transaction_id': 'tx-1',
        'space_id': 'space-1',
        'user_id': 'user-3',
        'amount_minor': 0,
        'currency': 'BRL',
        'created_at': '2026-07-28T00:00:00.000Z',
        'updated_at': '2026-07-28T00:00:00.000Z',
      });

      expect(parsed.amount.isZero, isTrue);
    });
  });

  group('toColumns', () {
    test('grava o valor em módulo e a data em UTC ISO-8601', () {
      final cols = split().toColumns();

      expect(cols['amount_minor'], 12000);
      expect(cols['currency'], 'BRL');
      expect(cols['created_at'], '2026-07-28T00:00:00.000Z');
    });

    test('a ida e volta preserva a parte', () {
      final original = split(userId: 'user-2', amountMinor: 333);
      final cols = original.toColumns();

      expect(ExpenseSplit.fromRow(cols), original);
    });
  });

  group('total', () {
    test('vazio não tem total — não há moeda para somar em', () {
      expect(const <ExpenseSplit>[].total, isNull);
    });

    test('uma parte', () {
      expect([split()].total, const Money.fromMinor(12000));
    });

    // O caso que a linha "Soma das partes" existe para provar: o centavo que
    // não divide não se perde no caminho.
    test(r'três partes de R$ 10,00 somam exatamente o total', () {
      final splits = [
        split(id: 's-1', amountMinor: 334),
        split(id: 's-2', userId: 'user-2', amountMinor: 333),
        split(id: 's-3', userId: 'user-3', amountMinor: 333),
      ];

      expect(splits.total, const Money.fromMinor(1000));
    });

    test('partes de zero não estragam a soma', () {
      final splits = [
        split(id: 's-1', amountMinor: 1),
        split(id: 's-2', userId: 'user-2', amountMinor: 0),
        split(id: 's-3', userId: 'user-3', amountMinor: 0),
      ];

      expect(splits.total, const Money.fromMinor(1));
    });

    // `Money.split` é quem faz o rateio na camada `data`. Este teste amarra a
    // promessa: o que ele devolve, somado, é o que entrou.
    test('o rateio de Money.split fecha o total em qualquer divisor', () {
      for (final parts in [1, 2, 3, 4, 5, 6, 7, 11, 13]) {
        const total = Money.fromMinor(10000);
        final shares = total.split(parts);

        expect(
          shares.fold<int>(0, (sum, s) => sum + s.amountMinor),
          10000,
          reason: 'rateio em $parts partes',
        );
      }
    });
  });
}
