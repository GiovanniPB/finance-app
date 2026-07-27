import 'package:core/core.dart';
import 'package:finance/features/accounts/data/accounts_repository_impl.dart';
import 'package:finance/features/accounts/domain/account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

/// ResultSet vazio para stubar `execute` (o retorno não é usado pelo repo).
ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

void main() {
  setUpAll(() => registerFallbackValue(<Object?>[]));

  late MockSqliteConnection db;
  late MockSupabaseClient supabase;
  late MockGoTrueClient auth;

  AccountsRepositoryImpl buildRepo() => AccountsRepositoryImpl(
    db: db,
    supabase: supabase,
    now: () => DateTime.utc(2026, 7, 14, 12),
    genId: () => 'acc-1',
  );

  setUp(() {
    db = MockSqliteConnection();
    supabase = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => supabase.auth).thenReturn(auth);
  });

  ResultSet oneAccountRow() => ResultSet(
    [
      'id',
      'owner_id',
      'linked_space_id',
      'name',
      'account_type',
      'institution',
      'currency',
      'current_balance_minor',
      'is_savings_target',
      'created_at',
      'updated_at',
    ],
    List<String?>.filled(11, null),
    [
      [
        'acc-1',
        'user-1',
        null,
        'Carteira',
        'checking',
        'Nubank',
        'BRL',
        25000,
        0,
        '2026-07-14T12:00:00.000Z',
        '2026-07-14T12:00:00.000Z',
      ],
    ],
  );

  Account testAccount() => Account(
    id: 'acc-1',
    ownerId: 'user-1',
    name: 'Conta corrente',
    type: AccountType.checking,
    currentBalance: const Money.fromMinor(25000),
    balanceAsOf: DateTime.utc(2026, 7, 14, 12),
    isSavingsTarget: false,
    createdAt: DateTime.utc(2026, 7, 14, 12),
    updatedAt: DateTime.utc(2026, 7, 14, 12),
    institution: 'Nubank',
  );

  void stubSession(String userId) {
    final user = MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.id).thenReturn(userId);
  }

  group('watchOwned', () {
    test('mapeia linhas do PowerSync para Account', () async {
      stubSession('user-1');
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(oneAccountRow()));

      final accounts = await buildRepo().watchOwned().first;
      expect(accounts, hasLength(1));
      expect(accounts.single.name, 'Carteira');
      expect(accounts.single.ownerId, 'user-1');
    });

    test('filtra por owner_id — ADR 0004, não vaza conta de outro membro', () {
      stubSession('user-1');
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(oneAccountRow()));

      buildRepo().watchOwned();

      final captured = verify(
        () => db.watch(
          captureAny(),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      expect(captured[0], contains('owner_id = ?'));
      expect(captured[1], ['user-1']);
    });

    test('sem sessão devolve lista vazia', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(await buildRepo().watchOwned().first, isEmpty);
      verifyNever(() => db.watch(any(), parameters: any(named: 'parameters')));
    });
  });

  group('watchForSpace', () {
    test('inclui as contas vinculadas ao household', () {
      stubSession('user-1');
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(oneAccountRow()));

      buildRepo().watchForSpace('space-1');

      final captured = verify(
        () => db.watch(
          captureAny(),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      expect(captured[0], contains('owner_id = ? OR linked_space_id = ?'));
      expect(captured[1], ['user-1', 'space-1']);
    });

    test('sem sessão devolve lista vazia', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(await buildRepo().watchForSpace('space-1').first, isEmpty);
    });
  });

  group('create', () {
    test('insere e retorna Ok quando há sessão', () async {
      final user = MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final result = await buildRepo().create(name: 'Carteira');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull?.id, 'acc-1');
      expect(result.valueOrNull?.ownerId, 'user-1');
      verify(
        () => db.execute(any(that: contains('INSERT INTO accounts')), any()),
      ).called(1);
    });

    test('retorna AuthFailure e não escreve quando sem sessão', () async {
      when(() => auth.currentUser).thenReturn(null);

      final result = await buildRepo().create(name: 'Carteira');

      expect(result.failureOrNull, isA<AuthFailure>());
      verifyNever(() => db.execute(any(), any()));
    });

    test('retorna DatabaseFailure quando o banco lança', () async {
      final user = MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(() => db.execute(any(), any())).thenThrow(Exception('db down'));

      final result = await buildRepo().create(name: 'Carteira');

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });

    test('grava tipo, instituição, saldo e alvo de poupança', () async {
      stubSession('user-1');
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final result = await buildRepo().create(
        name: 'Nubank',
        type: AccountType.creditCard,
        currentBalance: const Money.fromMinor(42000),
        isSavingsTarget: true,
        institution: 'Nu Pagamentos',
        linkedSpaceId: 'space-2',
      );

      final created = result.valueOrNull;
      expect(created?.type, AccountType.creditCard);
      expect(created?.institution, 'Nu Pagamentos');
      expect(created?.linkedSpaceId, 'space-2');
      expect(created?.isSavingsTarget, isTrue);

      final params =
          verify(
                () => db.execute(
                  any(that: contains('INSERT INTO accounts')),
                  captureAny(),
                ),
              ).captured.single
              as List<Object?>;
      expect(params, contains('credit_card'));
      expect(params, contains(42000));
      // Booleano vira 1/0: o SQLite não tem tipo booleano.
      expect(params, contains(1));
    });

    test('instituição em branco vira nulo, não string vazia', () async {
      stubSession('user-1');
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final result = await buildRepo().create(
        name: 'Carteira',
        institution: '   ',
      );

      expect(result.valueOrNull?.institution, isNull);
    });

    test('recusa nome vazio antes de tocar no banco', () async {
      stubSession('user-1');

      final result = await buildRepo().create(name: '   ');

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(any(), any()));
    });
  });

  group('update', () {
    test('grava os campos editáveis e renova o updated_at', () async {
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final repo = AccountsRepositoryImpl(
        db: db,
        supabase: supabase,
        now: () => DateTime.utc(2026, 7, 28, 9),
        genId: () => 'acc-1',
      );
      final result = await repo.update(
        testAccount().copyWith(name: 'Conta salário'),
      );

      expect(result.valueOrNull?.name, 'Conta salário');
      expect(result.valueOrNull?.updatedAt, DateTime.utc(2026, 7, 28, 9));

      final params =
          verify(
                () => db.execute(
                  any(that: contains('UPDATE accounts SET')),
                  captureAny(),
                ),
              ).captured.single
              as List<Object?>;
      // O id é o último parâmetro (cláusula WHERE), e owner_id não é editável.
      expect(params.last, 'acc-1');
      expect(params, isNot(contains('user-1')));
    });

    test('recusa nome vazio antes de tocar no banco', () async {
      final result = await buildRepo().update(
        testAccount().copyWith(name: ''),
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(any(), any()));
    });

    // A razão de `balance_as_of` existir: renomear a conta não pode fazer a
    // tela afirmar que o saldo foi conferido hoje.
    test('renomear não renova a data do saldo', () async {
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final repo = AccountsRepositoryImpl(
        db: db,
        supabase: supabase,
        now: () => DateTime.utc(2026, 7, 28, 9),
        genId: () => 'acc-1',
      );
      final result = await repo.update(
        testAccount().copyWith(name: 'Outro nome'),
      );

      expect(result.valueOrNull?.balanceAsOf, DateTime.utc(2026, 7, 14, 12));
      expect(result.valueOrNull?.updatedAt, DateTime.utc(2026, 7, 28, 9));
    });

    test('saldo novo renova a data do saldo', () async {
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final repo = AccountsRepositoryImpl(
        db: db,
        supabase: supabase,
        now: () => DateTime.utc(2026, 7, 28, 9),
        genId: () => 'acc-1',
      );
      final result = await repo.update(
        testAccount().copyWith(currentBalance: const Money.fromMinor(99900)),
        balanceChanged: true,
      );

      expect(result.valueOrNull?.balanceAsOf, DateTime.utc(2026, 7, 28, 9));
    });

    test('retorna DatabaseFailure quando o banco lança', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('db down'));

      final result = await buildRepo().update(testAccount());

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });
  });

  group('delete', () {
    test('remove e retorna Ok', () async {
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final result = await buildRepo().delete('acc-1');

      expect(result.isOk, isTrue);
      verify(
        () => db.execute(any(that: contains('DELETE FROM accounts')), any()),
      ).called(1);
    });

    test('retorna DatabaseFailure quando o banco lança', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('db down'));

      final result = await buildRepo().delete('acc-1');

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });
  });

  // Teste de guarda: o mock acima verifica o *texto* do SQL, então não pega
  // SQL que o SQLite recusa. As tabelas do PowerSync são views com triggers
  // `INSTEAD OF` — foi exatamente aí que o UPSERT de orçamento passou meses
  // quebrado com o teste verde. Aqui as statements rodam contra uma view igual.
  group('SQL de conta contra uma view como a do PowerSync', () {
    late CommonDatabase local;

    setUp(() {
      local = sqlite3.openInMemory()
        ..execute('''
          CREATE TABLE accounts_data (
            id TEXT PRIMARY KEY, owner_id TEXT, linked_space_id TEXT,
            name TEXT, account_type TEXT, institution TEXT, currency TEXT,
            current_balance_minor INTEGER, balance_as_of TEXT,
            is_savings_target INTEGER, created_at TEXT, updated_at TEXT
          );
        ''')
        ..execute('CREATE VIEW accounts AS SELECT * FROM accounts_data;')
        ..execute('''
          CREATE TRIGGER accounts_insert INSTEAD OF INSERT ON accounts BEGIN
            INSERT INTO accounts_data (id, owner_id, linked_space_id, name,
              account_type, institution, currency, current_balance_minor,
              balance_as_of, is_savings_target, created_at, updated_at)
            VALUES (new.id, new.owner_id, new.linked_space_id, new.name,
              new.account_type, new.institution, new.currency,
              new.current_balance_minor, new.balance_as_of,
              new.is_savings_target, new.created_at, new.updated_at);
          END;
        ''')
        ..execute('''
          CREATE TRIGGER accounts_update INSTEAD OF UPDATE ON accounts BEGIN
            UPDATE accounts_data SET linked_space_id = new.linked_space_id,
              name = new.name, account_type = new.account_type,
              institution = new.institution, currency = new.currency,
              current_balance_minor = new.current_balance_minor,
              balance_as_of = new.balance_as_of,
              is_savings_target = new.is_savings_target,
              updated_at = new.updated_at
            WHERE id = new.id;
          END;
        ''')
        ..execute('''
          CREATE TRIGGER accounts_delete INSTEAD OF DELETE ON accounts BEGIN
            DELETE FROM accounts_data WHERE id = old.id;
          END;
        ''');
    });

    tearDown(() => local.close());

    test('insert, watch e update rodam na view', () {
      local.execute(
        AccountSql.insert,
        AccountSql.insertParams(testAccount().toColumns()),
      );

      final owned = local.select(AccountSql.watchOwned, ['user-1']);
      expect(owned, hasLength(1));
      expect(owned.single['account_type'], 'checking');
      expect(owned.single['current_balance_minor'], 25000);

      local.execute(
        AccountSql.update,
        AccountSql.updateParams(
          testAccount()
              .copyWith(
                name: 'Conta salário',
                type: AccountType.creditCard,
                currentBalance: const Money.fromMinor(9900),
                isSavingsTarget: true,
                linkedSpaceId: 'space-2',
                updatedAt: DateTime.utc(2026, 7, 28, 9),
              )
              .toColumns(),
        ),
      );

      final after = local.select('SELECT * FROM accounts').single;
      expect(after['name'], 'Conta salário');
      expect(after['account_type'], 'credit_card');
      expect(after['current_balance_minor'], 9900);
      expect(after['is_savings_target'], 1);
      expect(after['linked_space_id'], 'space-2');
      // owner_id e created_at não estão no UPDATE: continuam os originais.
      expect(after['owner_id'], 'user-1');
      expect(after['created_at'], '2026-07-14T12:00:00.000Z');
    });

    test('watchForSpace enxerga a conta vinculada de outro dono', () {
      local
        ..execute(
          AccountSql.insert,
          AccountSql.insertParams(testAccount().toColumns()),
        )
        ..execute(
          AccountSql.insert,
          AccountSql.insertParams(
            testAccount()
                .copyWith(
                  id: 'acc-2',
                  ownerId: 'user-2',
                  name: 'Conta do casal',
                  linkedSpaceId: 'space-2',
                )
                .toColumns(),
          ),
        );

      expect(local.select(AccountSql.watchOwned, ['user-1']), hasLength(1));
      expect(
        local.select(AccountSql.watchForSpace, ['user-1', 'space-2']),
        hasLength(2),
      );
    });

    test('delete por id roda na view', () {
      local
        ..execute(
          AccountSql.insert,
          AccountSql.insertParams(testAccount().toColumns()),
        )
        ..execute(AccountSql.deleteById, ['acc-1']);

      expect(local.select('SELECT * FROM accounts'), isEmpty);
    });
  });
}
