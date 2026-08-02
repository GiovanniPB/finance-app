import 'package:core/core.dart';
import 'package:finance/features/transactions/data/settlement_repository_impl.dart';
import 'package:finance/features/transactions/domain/settlement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

class MockSqliteWriteContext extends Mock implements SqliteWriteContext {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

typedef WriteTxBool = Future<bool> Function(SqliteWriteContext tx);

Future<bool> _noopBoolTx(SqliteWriteContext tx) async => false;

void main() {
  setUpAll(() {
    registerFallbackValue(<Object?>[]);
    registerFallbackValue(_noopBoolTx);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // O SQL do saldo roda contra views iguais às do PowerSync.
  //
  // Mock de `SqliteConnection` verifica o *texto* do SQL, não se o SQLite o
  // aceita — e as tabelas locais são views com trigger `INSTEAD OF`, onde o
  // UPSERT de orçamento passou meses quebrado com o teste verde. Este grupo é o
  // único lugar que prova que a subquery derivada, o `UNION ALL` e o
  // `COALESCE(paid_by, created_by)` funcionam.
  // ─────────────────────────────────────────────────────────────────────────
  group('saldo com SQL de verdade', () {
    late CommonDatabase local;

    /// Roda a query do saldo e devolve o que a tela receberia.
    Settlement settlementOf(String spaceId) => settlementFromRows(
      local.select(SettlementSql.watchBalances, [spaceId, spaceId, spaceId]),
    );

    /// Grava um lançamento **pela view**, como o app faz.
    void transaction({
      required String id,
      required int minor,
      String spaceId = 'space-1',
      String createdBy = 'ana',
      String? paidBy,
      String type = 'expense',
      String currency = 'BRL',
    }) {
      local.execute(
        'INSERT INTO transactions (id, space_id, account_id, created_by, '
        'paid_by, type, amount_minor, currency, category_id, description, '
        'occurred_at, source, is_shared, ai_categorized, recurrence_id, '
        'created_at, updated_at) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, NULL, '
        "NULL, '2026-08-01', 'manual', 1, 0, NULL, '2026-08-01', "
        "'2026-08-01')",
        [id, spaceId, createdBy, paidBy, type, minor, currency],
      );
    }

    void split({
      required String transactionId,
      required String userId,
      required int minor,
      String spaceId = 'space-1',
      String currency = 'BRL',
    }) {
      local.execute(
        'INSERT INTO expense_splits (id, transaction_id, space_id, user_id, '
        'amount_minor, currency, created_at, updated_at) '
        "VALUES (?, ?, ?, ?, ?, ?, '2026-08-01', '2026-08-01')",
        [
          '$transactionId-$userId',
          transactionId,
          spaceId,
          userId,
          minor,
          currency,
        ],
      );
    }

    /// Uma despesa dividida igualmente entre [between], como `splitEqually`.
    void sharedExpense({
      required String id,
      required int minor,
      required List<String> between,
      String spaceId = 'space-1',
      String createdBy = 'ana',
      String? paidBy,
      String type = 'expense',
      String currency = 'BRL',
    }) {
      transaction(
        id: id,
        minor: minor,
        spaceId: spaceId,
        createdBy: createdBy,
        paidBy: paidBy,
        type: type,
        currency: currency,
      );
      final shares = Money.fromMinor(
        minor,
        currency: currency,
      ).split(between.length);
      for (var i = 0; i < between.length; i++) {
        split(
          transactionId: id,
          userId: between[i],
          minor: shares[i].amountMinor,
          spaceId: spaceId,
          currency: currency,
        );
      }
    }

    int netOf(Settlement settlement, String userId) =>
        settlement.balanceOf(userId)?.net.amountMinor ?? 0;

    setUp(() {
      local = sqlite3.openInMemory()
        ..execute('''
          CREATE TABLE transactions_data (
            id TEXT PRIMARY KEY, space_id TEXT, account_id TEXT,
            created_by TEXT, paid_by TEXT, type TEXT, amount_minor INTEGER,
            currency TEXT, category_id TEXT, description TEXT,
            occurred_at TEXT, source TEXT, is_shared INTEGER,
            ai_categorized INTEGER, recurrence_id TEXT,
            created_at TEXT, updated_at TEXT
          );
        ''')
        ..execute('''
          CREATE TABLE expense_splits_data (
            id TEXT PRIMARY KEY, transaction_id TEXT, space_id TEXT,
            user_id TEXT, amount_minor INTEGER, currency TEXT,
            created_at TEXT, updated_at TEXT
          );
        ''')
        ..execute('''
          CREATE TABLE spaces_data (
            id TEXT PRIMARY KEY, space_type TEXT
          );
        ''')
        ..execute(
          'CREATE VIEW transactions AS SELECT * FROM transactions_data;',
        )
        ..execute(
          'CREATE VIEW expense_splits AS SELECT * FROM expense_splits_data;',
        )
        ..execute('CREATE VIEW spaces AS SELECT * FROM spaces_data;')
        ..execute('''
          CREATE TRIGGER tx_insert INSTEAD OF INSERT ON transactions BEGIN
            INSERT INTO transactions_data (id, space_id, account_id, created_by,
              paid_by, type, amount_minor, currency, category_id, description,
              occurred_at, source, is_shared, ai_categorized, recurrence_id,
              created_at, updated_at)
            VALUES (new.id, new.space_id, new.account_id, new.created_by,
              new.paid_by, new.type, new.amount_minor, new.currency,
              new.category_id, new.description, new.occurred_at, new.source,
              new.is_shared, new.ai_categorized, new.recurrence_id,
              new.created_at, new.updated_at);
          END;
        ''')
        ..execute('''
          CREATE TRIGGER tx_delete INSTEAD OF DELETE ON transactions BEGIN
            DELETE FROM transactions_data WHERE id = old.id;
          END;
        ''')
        ..execute('''
          CREATE TRIGGER splits_insert INSTEAD OF INSERT ON expense_splits
          BEGIN
            INSERT INTO expense_splits_data (id, transaction_id, space_id,
              user_id, amount_minor, currency, created_at, updated_at)
            VALUES (new.id, new.transaction_id, new.space_id, new.user_id,
              new.amount_minor, new.currency, new.created_at, new.updated_at);
          END;
        ''')
        ..execute('''
          CREATE TRIGGER splits_delete INSTEAD OF DELETE ON expense_splits
          BEGIN
            DELETE FROM expense_splits_data WHERE id = old.id;
          END;
        ''')
        ..execute('''
          CREATE TRIGGER spaces_insert INSTEAD OF INSERT ON spaces BEGIN
            INSERT INTO spaces_data (id, space_type)
            VALUES (new.id, new.space_type);
          END;
        ''');
    });

    tearDown(() => local.close());

    test('espaço sem despesa dividida devolve "nada dividido"', () {
      expect(settlementOf('space-1').hasNothingSplit, isTrue);
    });

    test('a despesa dividida entre três vira saldo com o pagador certo', () {
      // Mercado de R$ 240 lançado pela Ana e pago pela **Carla**.
      sharedExpense(
        id: 'tx-1',
        minor: 24000,
        between: ['ana', 'bruno', 'carla'],
        paidBy: 'carla',
      );

      final settlement = settlementOf('space-1');

      expect(settlement.splitCount, 1);
      expect(netOf(settlement, 'carla'), 16000);
      expect(netOf(settlement, 'ana'), -8000);
      expect(netOf(settlement, 'bruno'), -8000);
      expect(settlement.transfers, hasLength(2));
    });

    test('paid_by nulo cai em created_by', () {
      sharedExpense(
        id: 'tx-1',
        minor: 24000,
        between: ['ana', 'bruno', 'carla'],
      );

      // Ninguém escolheu pagador: quem lançou (Ana) é quem adiantou.
      expect(netOf(settlementOf('space-1'), 'ana'), 16000);
    });

    test('despesa não dividida não entra no saldo', () {
      transaction(id: 'tx-1', minor: 24000);

      final settlement = settlementOf('space-1');

      expect(settlement.hasNothingSplit, isTrue);
      expect(settlement.transfers, isEmpty);
    });

    // `transfer` sem partes é pagamento de fatura vindo do Open Finance, e não
    // tem nada a ver com acerto. É o mesmo tipo do acerto, então sem a
    // exigência de partes ele contaria como dívida de quem pagou o cartão.
    test('transferência sem partes não entra no saldo', () {
      transaction(id: 'tx-1', minor: 50000, type: 'transfer');

      expect(settlementOf('space-1').hasNothingSplit, isTrue);
    });

    test('receita dividida não entra no saldo', () {
      sharedExpense(
        id: 'tx-1',
        minor: 30000,
        between: ['ana', 'bruno'],
        type: 'income',
      );

      expect(settlementOf('space-1').hasNothingSplit, isTrue);
    });

    test('lançamento de outro espaço não vaza', () {
      sharedExpense(
        id: 'tx-1',
        minor: 24000,
        between: ['ana', 'bruno'],
        spaceId: 'space-2',
      );

      expect(settlementOf('space-1').hasNothingSplit, isTrue);
      expect(settlementOf('space-2').splitCount, 1);
    });

    // O triângulo só existe onde a soma acontece: aqui. Três despesas em
    // círculo, valores iguais — o saldo líquido de todo mundo é zero, e é isso
    // que faz o guloso não propor transferência nenhuma. Par-a-par proporia
    // três que se cancelam.
    test('o triângulo se cancela no saldo, sem transferência nenhuma', () {
      sharedExpense(
        id: 'tx-1',
        minor: 6000,
        between: ['ana', 'bruno'],
        paidBy: 'ana',
      );
      sharedExpense(
        id: 'tx-2',
        minor: 6000,
        between: ['bruno', 'carla'],
        paidBy: 'bruno',
      );
      sharedExpense(
        id: 'tx-3',
        minor: 6000,
        between: ['carla', 'ana'],
        paidBy: 'carla',
      );

      final settlement = settlementOf('space-1');

      expect(settlement.splitCount, 3);
      expect(settlement.isAllSettled, isTrue);
      expect(settlement.transfers, isEmpty);
    });

    test('apagar o lançamento devolve o saldo ao anterior', () {
      sharedExpense(
        id: 'tx-1',
        minor: 24000,
        between: ['ana', 'bruno'],
        paidBy: 'ana',
      );
      sharedExpense(
        id: 'tx-2',
        minor: 10000,
        between: ['ana', 'bruno'],
        paidBy: 'bruno',
      );
      expect(netOf(settlementOf('space-1'), 'ana'), 7000);

      // Como o repositório de transações apaga: as partes à mão, porque view
      // não tem chave estrangeira e o `on delete cascade` do Postgres não
      // existe no aparelho.
      local
        ..execute('DELETE FROM expense_splits WHERE transaction_id = ?', [
          'tx-2',
        ])
        ..execute('DELETE FROM transactions WHERE id = ?', ['tx-2']);

      final after = settlementOf('space-1');
      expect(after.splitCount, 1);
      expect(netOf(after, 'ana'), 12000);
    });

    // Sumir com quem saiu esconderia dívida. A query não junta com
    // `space_members` de propósito: quem participou do rateio aparece, seja
    // membro ou não.
    test('quem saiu do espaço continua no saldo', () {
      sharedExpense(
        id: 'tx-1',
        minor: 20000,
        between: ['ana', 'quem-saiu'],
        paidBy: 'ana',
      );

      final settlement = settlementOf('space-1');

      expect(netOf(settlement, 'quem-saiu'), -10000);
      expect(settlement.transfers.single.fromUserId, 'quem-saiu');
    });

    test('o centavo indivisível não desaparece do saldo', () {
      // R$ 0,01 entre três, pago pela Ana: as partes são 1, 0 e 0.
      sharedExpense(
        id: 'tx-1',
        minor: 1,
        between: ['ana', 'bruno', 'carla'],
        paidBy: 'ana',
      );

      final settlement = settlementOf('space-1');
      final sum = settlement.balances.fold<int>(
        0,
        (total, b) => total + b.net.amountMinor,
      );

      expect(sum, 0);
      // Ana pagou 1 e deve 1: ninguém deve nada, e as partes de zero centavo
      // dizem a verdade sobre quem participou.
      expect(settlement.isAllSettled, isTrue);
    });

    test('duas moedas no mesmo espaço recusam somar', () {
      sharedExpense(
        id: 'tx-1',
        minor: 20000,
        between: ['ana', 'bruno'],
        paidBy: 'ana',
      );
      sharedExpense(
        id: 'tx-2',
        minor: 10000,
        between: ['ana', 'bruno'],
        paidBy: 'bruno',
        currency: 'USD',
      );

      final settlement = settlementOf('space-1');

      expect(settlement.isMixedCurrency, isTrue);
      expect(settlement.transfers, isEmpty);
    });

    // O acerto entra pela mesma porta: um `transfer` com uma parte só. É o que
    // dispensa tabela de acertos, e o que este teste prova é que a fórmula
    // `pagou − deve` zera o par sozinha.
    test('registrar o acerto zera o par, e só o par', () {
      sharedExpense(
        id: 'tx-1',
        minor: 24000,
        between: ['ana', 'bruno', 'carla'],
        paidBy: 'ana',
      );
      final before = settlementOf('space-1');
      expect(netOf(before, 'ana'), 16000);
      expect(netOf(before, 'bruno'), -8000);

      // Exatamente as duas statements do repositório.
      local
        ..execute(SettlementSql.insertTransfer, [
          'settle-1',
          'space-1',
          'carla',
          'bruno',
          'transfer',
          8000,
          'BRL',
          'Acerto com Ana',
          '2026-08-02',
          'manual',
          1,
          0,
          '2026-08-02',
          '2026-08-02',
        ])
        ..execute(SettlementSql.insertSplit, [
          'settle-split-1',
          'settle-1',
          'space-1',
          'ana',
          8000,
          'BRL',
          '2026-08-02',
          '2026-08-02',
        ]);

      final after = settlementOf('space-1');

      expect(netOf(after, 'bruno'), 0);
      expect(netOf(after, 'ana'), 8000);
      // Carla não foi tocada: o acerto zera o par, não o grupo.
      expect(netOf(after, 'carla'), -8000);
      expect(after.transfers, hasLength(1));
      expect(after.transfers.single.fromUserId, 'carla');
    });

    test('acertar o que já está quite não tem o que registrar', () {
      sharedExpense(
        id: 'tx-1',
        minor: 20000,
        between: ['ana', 'bruno'],
        paidBy: 'ana',
      );
      local
        ..execute(SettlementSql.insertTransfer, [
          'settle-1',
          'space-1',
          'bruno',
          'bruno',
          'transfer',
          10000,
          'BRL',
          null,
          '2026-08-02',
          'manual',
          1,
          0,
          '2026-08-02',
          '2026-08-02',
        ])
        ..execute(SettlementSql.insertSplit, [
          'settle-split-1',
          'settle-1',
          'space-1',
          'ana',
          10000,
          'BRL',
          '2026-08-02',
          '2026-08-02',
        ]);

      final settlement = settlementOf('space-1');

      expect(settlement.isAllSettled, isTrue);
      expect(settlement.transfersInvolving('ana'), isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // O que o SQL não responde: sessão, validação, e as duas linhas juntas.
  // ─────────────────────────────────────────────────────────────────────────
  group('settle', () {
    late MockSqliteConnection db;
    late MockSqliteWriteContext tx;
    late MockSupabaseClient supabase;
    late MockGoTrueClient auth;
    late List<String> txSql;

    SettlementRepositoryImpl buildRepo() => SettlementRepositoryImpl(
      db: db,
      supabase: supabase,
      now: () => DateTime.utc(2026, 8, 2, 12),
      genId: () => 'gen-1',
    );

    void stubSession() {
      final user = MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.id).thenReturn('ana');
    }

    setUp(() {
      db = MockSqliteConnection();
      tx = MockSqliteWriteContext();
      supabase = MockSupabaseClient();
      auth = MockGoTrueClient();
      txSql = [];
      when(() => supabase.auth).thenReturn(auth);
      when(() => tx.getAll(any(), any())).thenAnswer(
        (_) async => ResultSet(
          const ['space_type'],
          const [],
          const [
            ['group'],
          ],
        ),
      );
      when(() => tx.execute(any(), any())).thenAnswer((invocation) async {
        txSql.add(invocation.positionalArguments.first as String);
        return emptyResultSet();
      });
      when(() => db.writeTransaction<bool>(any())).thenAnswer((
        invocation,
      ) async {
        final callback = invocation.positionalArguments.first as WriteTxBool;
        return callback(tx);
      });
    });

    test('sem sessão, recusa', () async {
      when(() => auth.currentUser).thenReturn(null);

      final result = await buildRepo().settle(
        spaceId: 'space-1',
        fromUserId: 'bruno',
        toUserId: 'ana',
        amount: const Money.fromMinor(8000),
      );

      expect(result, isA<Err<void, Failure>>());
      expect(txSql, isEmpty);
    });

    test('valor não positivo é recusado antes de qualquer escrita', () async {
      stubSession();

      final result = await buildRepo().settle(
        spaceId: 'space-1',
        fromUserId: 'bruno',
        toUserId: 'ana',
        amount: const Money.zero(),
      );

      expect(result, isA<Err<void, Failure>>());
      expect(txSql, isEmpty);
    });

    test('ninguém acerta consigo mesmo', () async {
      stubSession();

      final result = await buildRepo().settle(
        spaceId: 'space-1',
        fromUserId: 'ana',
        toUserId: 'ana',
        amount: const Money.fromMinor(8000),
      );

      expect(result, isA<Err<void, Failure>>());
      expect(txSql, isEmpty);
    });

    test('espaço que não é grupo é recusado', () async {
      stubSession();
      when(() => tx.getAll(any(), any())).thenAnswer(
        (_) async => ResultSet(
          const ['space_type'],
          const [],
          const [
            ['household'],
          ],
        ),
      );

      final result = await buildRepo().settle(
        spaceId: 'space-1',
        fromUserId: 'bruno',
        toUserId: 'ana',
        amount: const Money.fromMinor(8000),
      );

      expect(result, isA<Err<void, Failure>>());
      expect(txSql, isEmpty);
    });

    // As duas linhas na mesma `writeTransaction`, pelo mesmo argumento que faz
    // `is_shared` e as partes nascerem juntas.
    test('grava o transfer e a parte numa transação só', () async {
      stubSession();

      final result = await buildRepo().settle(
        spaceId: 'space-1',
        fromUserId: 'bruno',
        toUserId: 'ana',
        amount: const Money.fromMinor(8000),
        description: 'Acerto com Bruno',
      );

      expect(result, isA<Ok<void, Failure>>());
      expect(txSql, hasLength(2));
      expect(txSql.first, contains('INSERT INTO transactions'));
      expect(txSql.last, contains('INSERT INTO expense_splits'));
    });

    test('quem registra não é quem paga: created_by é a sessão', () async {
      stubSession();

      await buildRepo().settle(
        spaceId: 'space-1',
        fromUserId: 'bruno',
        toUserId: 'ana',
        amount: const Money.fromMinor(8000),
      );

      final params =
          verify(
                () => tx.execute(
                  any(that: contains('INSERT INTO transactions')),
                  captureAny(),
                ),
              ).captured.single
              as List<Object?>;

      // A policy de INSERT do Postgres exige `created_by = auth.uid()`; o
      // pagador é a outra ponta. Os dois campos existem justamente para isso.
      expect(params[2], 'ana');
      expect(params[3], 'bruno');
    });
  });
}
