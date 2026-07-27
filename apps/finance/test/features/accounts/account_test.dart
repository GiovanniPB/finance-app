import 'package:core/core.dart';
import 'package:finance/features/accounts/domain/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountType', () {
    test('mapeia os tipos do banco', () {
      expect(AccountType.fromDb('checking'), AccountType.checking);
      expect(AccountType.fromDb('savings'), AccountType.savings);
      expect(AccountType.fromDb('credit_card'), AccountType.creditCard);
      expect(AccountType.fromDb('investment'), AccountType.investment);
      expect(AccountType.fromDb('cash'), AccountType.cash);
      expect(AccountType.fromDb('other'), AccountType.other);
    });

    test('rejeita tipo desconhecido', () {
      expect(() => AccountType.fromDb('crypto'), throwsArgumentError);
    });

    test('db usa snake_case — o check da migration não aceita camelCase', () {
      expect(AccountType.creditCard.db, 'credit_card');
      expect(AccountType.checking.db, 'checking');
    });

    test('roundtrip fromDb(db) vale para todo tipo', () {
      for (final type in AccountType.values) {
        expect(AccountType.fromDb(type.db), type);
      }
    });

    test('só cartão de crédito guarda dívida', () {
      expect(AccountType.creditCard.isDebt, isTrue);
      for (final other in AccountType.values.where((t) => !t.isDebt)) {
        expect(other, isNot(AccountType.creditCard));
      }
    });

    test('todo tipo tem rótulo', () {
      for (final type in AccountType.values) {
        expect(type.label, isNotEmpty);
      }
    });
  });

  group('Account — mapeamento', () {
    final row = <String, Object?>{
      'id': 'acc-1',
      'owner_id': 'user-1',
      'linked_space_id': null,
      'name': 'Carteira',
      'account_type': 'cash',
      'institution': null,
      'currency': 'BRL',
      'current_balance_minor': 25000,
      'is_savings_target': 0,
      'created_at': '2026-07-14T12:00:00.000Z',
      'updated_at': '2026-07-14T12:30:00.000Z',
    };

    test('fromRow mapeia todas as colunas', () {
      final account = Account.fromRow(row);

      expect(account.id, 'acc-1');
      expect(account.ownerId, 'user-1');
      expect(account.name, 'Carteira');
      expect(account.type, AccountType.cash);
      expect(account.currentBalance, const Money.fromMinor(25000));
      expect(account.currency, 'BRL');
      expect(account.isSavingsTarget, isFalse);
      expect(account.institution, isNull);
      expect(account.linkedSpaceId, isNull);
      expect(account.createdAt, DateTime.utc(2026, 7, 14, 12));
      expect(account.updatedAt, DateTime.utc(2026, 7, 14, 12, 30));
    });

    test('fromRow lê os booleanos como inteiro do SQLite', () {
      final flagged = Account.fromRow({...row, 'is_savings_target': 1});

      expect(flagged.isSavingsTarget, isTrue);
    });

    // Linha gravada antes da migration 20260727210000 não tem as colunas
    // novas. Ler tem de continuar funcionando, com o mesmo default do banco.
    test('fromRow tolera linha anterior às colunas novas', () {
      final legacy = Account.fromRow({
        'id': 'acc-1',
        'owner_id': 'user-1',
        'name': 'Carteira',
        'currency': 'BRL',
        'created_at': '2026-07-14T12:00:00.000Z',
        'updated_at': '2026-07-14T12:00:00.000Z',
      });

      expect(legacy.type, AccountType.checking);
      expect(legacy.currentBalance, const Money.zero());
      expect(legacy.isSavingsTarget, isFalse);
    });

    test('toColumns produz as chaves do schema com datas ISO UTC', () {
      final cols = Account.fromRow(row).toColumns();

      expect(cols.keys, containsAll(row.keys));
      expect(cols['account_type'], 'cash');
      expect(cols['is_savings_target'], 0);
      expect(cols['created_at'], '2026-07-14T12:00:00.000Z');
    });

    test('toColumns grava o saldo sem sinal — a direção vem do tipo', () {
      final card = Account.fromRow(row).copyWith(
        type: AccountType.creditCard,
        currentBalance: const Money.fromMinor(-42000),
      );

      expect(card.toColumns()['current_balance_minor'], 42000);
    });

    test('roundtrip fromRow -> toColumns -> fromRow preserva a entidade', () {
      final original = Account.fromRow({
        ...row,
        'account_type': 'credit_card',
        'institution': 'Nubank',
        'linked_space_id': 'space-2',
        'is_savings_target': 1,
      });

      expect(Account.fromRow(original.toColumns()), original);
    });
  });

  group('Account — derivados', () {
    Account account({
      AccountType type = AccountType.checking,
      int balanceMinor = 25000,
      String? linkedSpaceId,
    }) => Account(
      id: 'acc-1',
      ownerId: 'user-1',
      name: 'Conta',
      type: type,
      currentBalance: Money.fromMinor(balanceMinor),
      isSavingsTarget: false,
      createdAt: DateTime.utc(2026, 7, 14),
      updatedAt: DateTime.utc(2026, 7, 14),
      linkedSpaceId: linkedSpaceId,
    );

    test('signedBalance é positivo em conta de dinheiro disponível', () {
      expect(account().signedBalance, const Money.fromMinor(25000));
    });

    test('signedBalance é negativo em cartão — a fatura é dívida', () {
      expect(
        account(type: AccountType.creditCard).signedBalance,
        const Money.fromMinor(-25000),
      );
    });

    test('signedBalance normaliza saldo já digitado com sinal', () {
      expect(
        account(
          type: AccountType.creditCard,
          balanceMinor: -25000,
        ).signedBalance,
        const Money.fromMinor(-25000),
      );
      expect(
        account(balanceMinor: -25000).signedBalance,
        const Money.fromMinor(25000),
      );
    });

    test('signedBalance preserva a moeda', () {
      final dollars = account().copyWith(
        currentBalance: const Money.fromMinor(1000, currency: 'USD'),
      );

      expect(dollars.signedBalance.currency, 'USD');
    });

    test('conta sem vínculo não é compartilhada com household', () {
      expect(account().isSharedWithHousehold, isFalse);
      expect(account(linkedSpaceId: 'space-2').isSharedWithHousehold, isTrue);
    });
  });
}
