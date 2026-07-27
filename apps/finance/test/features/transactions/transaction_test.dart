import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> row({
    String type = 'expense',
    int amountMinor = 14280,
    String? categoryId = 'cat-1',
    int isShared = 0,
    String source = 'manual',
  }) => {
    'id': 'tx-1',
    'space_id': 'space-1',
    'account_id': 'acc-1',
    'created_by': 'user-1',
    'type': type,
    'amount_minor': amountMinor,
    'currency': 'BRL',
    'category_id': categoryId,
    'description': 'Mercado',
    'occurred_at': '2026-07-27T12:00:00.000Z',
    'source': source,
    'is_shared': isShared,
    'ai_categorized': 0,
    'recurrence_id': null,
    'created_at': '2026-07-27T12:00:00.000Z',
    'updated_at': '2026-07-27T12:00:00.000Z',
  };

  group('TransactionType', () {
    test('mapeia os quatro tipos do banco', () {
      expect(TransactionType.fromDb('expense'), TransactionType.expense);
      expect(TransactionType.fromDb('income'), TransactionType.income);
      expect(TransactionType.fromDb('transfer'), TransactionType.transfer);
      expect(TransactionType.fromDb('savings'), TransactionType.savings);
    });

    test('rejeita tipo desconhecido', () {
      expect(() => TransactionType.fromDb('nope'), throwsArgumentError);
    });

    test('despesa e poupança são saída; receita e transferência não são', () {
      // Poupança conta como saída: o dinheiro deixa o saldo gastável mesmo sem
      // ser despesa.
      expect(TransactionType.expense.isOutflow, isTrue);
      expect(TransactionType.savings.isOutflow, isTrue);
      expect(TransactionType.income.isOutflow, isFalse);
      expect(TransactionType.transfer.isOutflow, isFalse);
    });

    test('o valor de banco é o nome do enum', () {
      expect(TransactionType.expense.db, 'expense');
      expect(TransactionType.savings.db, 'savings');
    });
  });

  group('TransactionSource', () {
    test('mapeia snake_case do banco', () {
      expect(TransactionSource.fromDb('manual'), TransactionSource.manual);
      expect(
        TransactionSource.fromDb('open_finance'),
        TransactionSource.openFinance,
      );
    });

    test('serializa openFinance como open_finance', () {
      expect(TransactionSource.openFinance.db, 'open_finance');
      expect(TransactionSource.manual.db, 'manual');
    });

    test('rejeita origem desconhecida', () {
      expect(() => TransactionSource.fromDb('csv'), throwsArgumentError);
    });
  });

  group('Transaction.fromRow — sinal do valor', () {
    test('despesa vira Money negativo no domínio', () {
      final transaction = Transaction.fromRow(row());

      expect(transaction.amount.amountMinor, -14280);
      expect(transaction.amount.isNegative, isTrue);
    });

    test('receita vira Money positivo', () {
      final transaction = Transaction.fromRow(
        row(type: 'income', amountMinor: 540000),
      );

      expect(transaction.amount.amountMinor, 540000);
      expect(transaction.isIncome, isTrue);
    });

    test('poupança também vira negativo', () {
      final transaction = Transaction.fromRow(row(type: 'savings'));

      expect(transaction.amount.isNegative, isTrue);
    });

    test('ignora sinal espúrio vindo da coluna', () {
      // A coluna tem constraint > 0, mas se algo escapar, o tipo manda.
      final expense = Transaction.fromRow(row(amountMinor: -14280));
      final income = Transaction.fromRow(
        row(type: 'income', amountMinor: -540000),
      );

      expect(expense.amount.amountMinor, -14280);
      expect(income.amount.amountMinor, 540000);
    });

    test('mapeia os demais campos', () {
      final transaction = Transaction.fromRow(row());

      expect(transaction.id, 'tx-1');
      expect(transaction.spaceId, 'space-1');
      expect(transaction.accountId, 'acc-1');
      expect(transaction.createdBy, 'user-1');
      expect(transaction.categoryId, 'cat-1');
      expect(transaction.description, 'Mercado');
      expect(transaction.amount.currency, 'BRL');
      expect(transaction.occurredAt, DateTime.utc(2026, 7, 27, 12));
    });

    test('booleanos chegam como inteiro do PowerSync', () {
      expect(Transaction.fromRow(row()).isShared, isFalse);
      expect(Transaction.fromRow(row(isShared: 1)).isShared, isTrue);
    });

    test('categoria nula é aceita', () {
      expect(Transaction.fromRow(row(categoryId: null)).categoryId, isNull);
    });

    test('isAutomatic distingue Open Finance de manual', () {
      expect(Transaction.fromRow(row()).isAutomatic, isFalse);
      expect(
        Transaction.fromRow(row(source: 'open_finance')).isAutomatic,
        isTrue,
      );
    });
  });

  group('Transaction.toColumns', () {
    test('persiste o valor em módulo, sem sinal', () {
      final transaction = Transaction.fromRow(row());
      final cols = transaction.toColumns();

      expect(transaction.amount.amountMinor, -14280);
      expect(cols['amount_minor'], 14280);
      expect(cols['type'], 'expense');
    });

    test('receita também é persistida positiva', () {
      final cols = Transaction.fromRow(
        row(type: 'income', amountMinor: 540000),
      ).toColumns();

      expect(cols['amount_minor'], 540000);
    });

    test('booleanos voltam a inteiro', () {
      final cols = Transaction.fromRow(row(isShared: 1)).toColumns();

      expect(cols['is_shared'], 1);
      expect(cols['ai_categorized'], 0);
    });

    test('round-trip preserva a entidade', () {
      final original = Transaction.fromRow(row());
      final roundTripped = Transaction.fromRow({
        ...original.toColumns(),
        // fromRow espera inteiro; toColumns já devolve inteiro.
      });

      expect(roundTripped, original);
    });

    test('datas viram ISO-8601 em UTC', () {
      final cols = Transaction.fromRow(row()).toColumns();

      expect(cols['occurred_at'], '2026-07-27T12:00:00.000Z');
      expect(cols['created_at'], '2026-07-27T12:00:00.000Z');
    });
  });

  group('Transaction — imutabilidade', () {
    test('copyWith gera nova instância sem mutar a original', () {
      final original = Transaction.fromRow(row());
      final changed = original.copyWith(description: 'Padaria');

      expect(original.description, 'Mercado');
      expect(changed.description, 'Padaria');
      expect(changed.amount, original.amount);
    });

    test('igualdade é por valor', () {
      expect(Transaction.fromRow(row()), Transaction.fromRow(row()));
      expect(
        Transaction.fromRow(row()),
        isNot(Transaction.fromRow(row(amountMinor: 1))),
      );
    });
  });
}
