import 'package:core/core.dart';
import 'package:finance/features/transactions/domain/month_summary.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Transaction tx({
    required int minor,
    TransactionType type = TransactionType.expense,
    String? categoryId = 'cat-1',
    String id = 'tx',
  }) => Transaction(
    id: id,
    spaceId: 'space-1',
    createdBy: 'user-1',
    paidBy: 'user-1',
    type: type,
    amount: Money.fromMinor(type.isOutflow ? -minor.abs() : minor.abs()),
    occurredAt: DateTime.utc(2026, 7, 15),
    source: TransactionSource.manual,
    isShared: false,
    aiCategorized: false,
    createdAt: DateTime.utc(2026, 7, 15),
    updatedAt: DateTime.utc(2026, 7, 15),
    categoryId: categoryId,
  );

  group('MonthSummary.empty', () {
    test('tudo zerado e sem categorias', () {
      expect(MonthSummary.empty.income.isZero, isTrue);
      expect(MonthSummary.empty.outflow.isZero, isTrue);
      expect(MonthSummary.empty.balance.isZero, isTrue);
      expect(MonthSummary.empty.spentByCategory, isEmpty);
    });
  });

  group('MonthSummary.from', () {
    test('lista vazia resulta em tudo zero', () {
      final summary = MonthSummary.from(const []);

      expect(summary.income.isZero, isTrue);
      expect(summary.outflow.isZero, isTrue);
      expect(summary.balance.isZero, isTrue);
    });

    test('soma entradas e saídas separadamente', () {
      final summary = MonthSummary.from([
        tx(minor: 14280),
        tx(minor: 1250, id: 'tx-2'),
        tx(minor: 540000, type: TransactionType.income, id: 'tx-3'),
      ]);

      expect(summary.income.amountMinor, 540000);
      expect(summary.outflow.amountMinor, 15530);
    });

    test('outflow é sempre positivo, mesmo somando valores negativos', () {
      final summary = MonthSummary.from([tx(minor: 14280)]);

      expect(summary.outflow.isPositive, isTrue);
      expect(summary.outflow.amountMinor, 14280);
    });

    test('balance é entradas menos saídas', () {
      final summary = MonthSummary.from([
        tx(minor: 10000),
        tx(minor: 30000, type: TransactionType.income, id: 'tx-2'),
      ]);

      expect(summary.balance.amountMinor, 20000);
    });

    test('balance fica negativo quando saiu mais do que entrou', () {
      final summary = MonthSummary.from([
        tx(minor: 50000),
        tx(minor: 10000, type: TransactionType.income, id: 'tx-2'),
      ]);

      expect(summary.balance.amountMinor, -40000);
      expect(summary.balance.isNegative, isTrue);
    });

    test('poupança entra como saída', () {
      final summary = MonthSummary.from([
        tx(minor: 20000, type: TransactionType.savings),
      ]);

      expect(summary.outflow.amountMinor, 20000);
      expect(summary.income.isZero, isTrue);
    });

    test('transferência não conta em nenhum dos dois lados', () {
      // Esta asserção era o inverso, e chamava-se "convenção da Fase 0" —
      // inofensiva enquanto nada no produto produzia `transfer`. Quando a
      // ingestão do Open Finance passou a gravar pagamento de fatura como
      // `transfer`, a home exibiu R$ 10.641,79 de "Entradas" que eram dinheiro
      // trocando de bolso. O teste antigo protegia o bug.
      final summary = MonthSummary.from([
        tx(minor: 20000, type: TransactionType.transfer),
      ]);

      expect(summary.income.isZero, isTrue);
      expect(summary.outflow.isZero, isTrue);
      expect(summary.balance.isZero, isTrue);
    });

    test('transferência não afeta o saldo do mês', () {
      final semTransferencia = MonthSummary.from([
        tx(minor: 30000, type: TransactionType.income),
        tx(minor: 10000, id: 'tx-2'),
      ]);
      final comTransferencia = MonthSummary.from([
        tx(minor: 30000, type: TransactionType.income),
        tx(minor: 10000, id: 'tx-2'),
        tx(minor: 1013902, type: TransactionType.transfer, id: 'tx-3'),
      ]);

      expect(comTransferencia.balance, semTransferencia.balance);
      expect(comTransferencia.income, semTransferencia.income);
    });
  });

  group('MonthSummary — acumulado por categoria', () {
    test('agrupa saídas da mesma categoria', () {
      final summary = MonthSummary.from([
        tx(minor: 14280),
        tx(minor: 1250, id: 'tx-2'),
        tx(minor: 5000, categoryId: 'cat-2', id: 'tx-3'),
      ]);

      expect(summary.spentIn('cat-1').amountMinor, 15530);
      expect(summary.spentIn('cat-2').amountMinor, 5000);
    });

    test('categoria sem gasto devolve zero, não null', () {
      final summary = MonthSummary.from([tx(minor: 100)]);

      expect(summary.spentIn('inexistente').isZero, isTrue);
    });

    test('receita não entra no acumulado por categoria', () {
      final summary = MonthSummary.from([
        tx(minor: 540000, type: TransactionType.income, categoryId: 'cat-9'),
      ]);

      expect(summary.spentIn('cat-9').isZero, isTrue);
      expect(summary.spentByCategory, isEmpty);
    });

    test('saída sem categoria conta no total mas não no acumulado', () {
      final summary = MonthSummary.from([tx(minor: 8000, categoryId: null)]);

      // Não há orçamento a debitar, mas o dinheiro saiu.
      expect(summary.outflow.amountMinor, 8000);
      expect(summary.spentByCategory, isEmpty);
    });

    test('o mapa de categorias é imutável', () {
      final summary = MonthSummary.from([tx(minor: 100)]);

      expect(
        () => summary.spentByCategory['cat-x'] = const Money.zero(),
        throwsUnsupportedError,
      );
    });
  });
}
