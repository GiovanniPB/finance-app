import 'package:core/core.dart';
import 'package:finance/features/transactions/data/transactions_repository_impl.dart';
import 'package:finance/features/transactions/domain/expense_split.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

class MockSqliteWriteContext extends Mock implements SqliteWriteContext {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

ResultSet resultSetOf(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return emptyResultSet();
  final columns = rows.first.keys.toList();
  return ResultSet(columns, const [], [
    for (final row in rows) [for (final c in columns) row[c]],
  ]);
}

/// As duas formas de callback de `writeTransaction` que este repositório usa.
///
/// Duas e não uma porque `writeTransaction` é genérico: `update` e `delete`
/// devolvem `void`, `splitEqually` devolve a lista de partes. O mocktail casa o
/// stub pelo argumento de tipo, então cada forma precisa do seu.
typedef WriteTxVoid = Future<void> Function(SqliteWriteContext tx);
typedef WriteTxSplits =
    Future<List<ExpenseSplit>?> Function(SqliteWriteContext tx);

Future<void> _noopTx(SqliteWriteContext tx) async {}
Future<List<ExpenseSplit>?> _noopSplitsTx(SqliteWriteContext tx) async => null;

void main() {
  setUpAll(() {
    registerFallbackValue(<Object?>[]);
    // O tipo vem da declaração das funções, não de um argumento de tipo:
    // `registerFallbackValue` do mocktail 1.x recebe `dynamic`.
    registerFallbackValue(_noopTx);
    registerFallbackValue(_noopSplitsTx);
  });

  late MockSqliteConnection db;
  late MockSqliteWriteContext tx;
  late MockSupabaseClient supabase;
  late MockGoTrueClient auth;

  /// SQL e parâmetros executados dentro da `writeTransaction`, na ordem.
  late List<String> txSql;
  final txParams = <List<Object?>>[];

  TransactionsRepositoryImpl buildRepo() => TransactionsRepositoryImpl(
    db: db,
    supabase: supabase,
    now: () => DateTime.utc(2026, 7, 27, 12),
    genId: () => 'tx-1',
  );

  void stubSession() {
    final user = MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.id).thenReturn('user-1');
  }

  void stubExecute() {
    when(
      () => db.execute(any(), any()),
    ).thenAnswer((_) async => emptyResultSet());
  }

  setUp(() {
    db = MockSqliteConnection();
    tx = MockSqliteWriteContext();
    supabase = MockSupabaseClient();
    auth = MockGoTrueClient();
    txSql = [];
    when(() => supabase.auth).thenReturn(auth);
    when(
      () => db.watch(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((_) => Stream.value(emptyResultSet()));
    // Sem parte nenhuma é o padrão: `update` lê isto para derivar `is_shared`
    // em vez de acreditar na entidade que veio da tela.
    when(() => tx.getAll(any(), any())).thenAnswer((_) async {
      return emptyResultSet();
    });
    when(() => tx.execute(any(), any())).thenAnswer((invocation) async {
      txSql.add(invocation.positionalArguments.first as String);
      txParams.add(invocation.positionalArguments[1] as List<Object?>);
      return emptyResultSet();
    });
    when(() => db.writeTransaction<void>(any())).thenAnswer((
      invocation,
    ) async {
      final callback = invocation.positionalArguments.first as WriteTxVoid;
      await callback(tx);
    });
  });

  group('watchBySpace — escopo de espaço (ADR 0004)', () {
    test('sempre filtra por space_id', () {
      buildRepo().watchBySpace('space-1');

      final captured = verify(
        () => db.watch(
          captureAny(),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      expect(captured[0], contains('space_id = ?'));
      expect(captured[1], ['space-1']);
    });

    test('acrescenta a janela de datas quando informada', () {
      buildRepo().watchBySpace(
        'space-1',
        from: DateTime.utc(2026, 7),
        to: DateTime.utc(2026, 8),
      );

      final captured = verify(
        () => db.watch(
          captureAny(),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      final sql = captured[0] as String;
      // `datetime()` nos dois lados é a correção do mês que perdia o dia 1º: o
      // PowerSync guarda a data com **espaço** (`2026-07-01 05:00:00.000Z`) e o
      // parâmetro vem com **T**, então comparação de texto crua reprovava o dia
      // 1º e aprovava o dia 1º do mês seguinte.
      //
      // Esta asserção é sobre o **texto** do SQL, e texto não prova
      // comportamento — o que prova é o teste de integração "o dia 1º do mês
      // não desaparece quando a linha veio da sincronização", que roda contra
      // um PowerSync real com a linha no formato da sincronização.
      expect(sql, contains('datetime(occurred_at) >= datetime(?)'));
      expect(sql, contains('datetime(occurred_at) < datetime(?)'));
      expect(captured[1], [
        'space-1',
        '2026-07-01T00:00:00.000Z',
        '2026-08-01T00:00:00.000Z',
      ]);
    });

    test('ordena por data decrescente', () {
      buildRepo().watchBySpace('space-1');

      final sql =
          verify(
                () => db.watch(
                  captureAny(),
                  parameters: any(named: 'parameters'),
                ),
              ).captured.single
              as String;
      expect(sql, contains('ORDER BY occurred_at DESC'));
    });
  });

  group('create', () {
    test('grava valor em módulo e devolve entidade com sinal', () async {
      stubSession();
      stubExecute();

      final result = await buildRepo().create(
        spaceId: 'space-1',
        type: TransactionType.expense,
        amount: const Money.fromMinor(14280),
        occurredAt: DateTime.utc(2026, 7, 27),
        categoryId: 'cat-1',
      );

      final transaction = switch (result) {
        Ok(:final value) => value,
        Err() => fail('esperava Ok'),
      };
      // Domínio com sinal…
      expect(transaction.amount.amountMinor, -14280);
      // …banco em módulo.
      final params =
          verify(
                () => db.execute(any(), captureAny()),
              ).captured.single
              as List<Object?>;
      expect(params, contains(14280));
    });

    test('normaliza sinal de entrada conforme o tipo', () async {
      stubSession();
      stubExecute();

      final result = await buildRepo().create(
        spaceId: 'space-1',
        type: TransactionType.income,
        // Usuário/tela passou negativo por engano.
        amount: const Money.fromMinor(-540000),
        occurredAt: DateTime.utc(2026, 7, 27),
      );

      final transaction = switch (result) {
        Ok(:final value) => value,
        Err() => fail('esperava Ok'),
      };
      expect(transaction.amount.amountMinor, 540000);
    });

    test('marca a origem como manual', () async {
      stubSession();
      stubExecute();

      final result = await buildRepo().create(
        spaceId: 'space-1',
        type: TransactionType.expense,
        amount: const Money.fromMinor(100),
        occurredAt: DateTime.utc(2026, 7, 27),
      );

      expect(
        result.valueOrNull?.source,
        TransactionSource.manual,
      );
    });

    test('sem sessão devolve AuthFailure', () async {
      when(() => auth.currentUser).thenReturn(null);

      final result = await buildRepo().create(
        spaceId: 'space-1',
        type: TransactionType.expense,
        amount: const Money.fromMinor(100),
        occurredAt: DateTime.utc(2026, 7, 27),
      );

      expect(result, isA<Err<Transaction, Failure>>());
      expect(
        result.failureOrNull,
        isA<AuthFailure>(),
      );
      verifyNever(() => db.execute(any(), any()));
    });

    test('valor zero devolve ValidationFailure', () async {
      stubSession();

      final result = await buildRepo().create(
        spaceId: 'space-1',
        type: TransactionType.expense,
        amount: const Money.zero(),
        occurredAt: DateTime.utc(2026, 7, 27),
      );

      expect(
        result.failureOrNull,
        isA<ValidationFailure>(),
      );
      verifyNever(() => db.execute(any(), any()));
    });

    test('erro do banco vira DatabaseFailure, sem vazar exception', () async {
      stubSession();
      when(() => db.execute(any(), any())).thenThrow(Exception('disco cheio'));

      final result = await buildRepo().create(
        spaceId: 'space-1',
        type: TransactionType.expense,
        amount: const Money.fromMinor(100),
        occurredAt: DateTime.utc(2026, 7, 27),
      );

      expect(
        result.failureOrNull,
        isA<DatabaseFailure>(),
      );
    });
  });

  group('update', () {
    Transaction existing() => Transaction(
      id: 'tx-1',
      spaceId: 'space-1',
      createdBy: 'user-1',
      paidBy: 'user-1',
      type: TransactionType.expense,
      amount: const Money.fromMinor(-14280),
      occurredAt: DateTime.utc(2026, 7, 27),
      source: TransactionSource.manual,
      isShared: false,
      aiCategorized: false,
      createdAt: DateTime.utc(2026, 7, 27),
      updatedAt: DateTime.utc(2026, 7, 27),
    );

    test('atualiza updated_at e devolve a entidade nova', () async {
      final result = await buildRepo().update(
        existing().copyWith(description: 'Padaria'),
      );

      final updated = switch (result) {
        Ok(:final value) => value,
        Err() => fail('esperava Ok'),
      };
      expect(updated.description, 'Padaria');
      expect(updated.updatedAt, DateTime.utc(2026, 7, 27, 12));
    });

    // O furo que a leitura dentro da transação fecha: a folha de edição carrega
    // o lançamento como ele estava **ao abrir**. Dividir e salvar em seguida
    // mandaria `is_shared = 0` de volta, apagando a marca e deixando as partes
    // órfãs — sem erro nenhum.
    test('is_shared é derivado da tabela de partes, não da entidade', () async {
      when(() => tx.getAll(ExpenseSplitSql.byTransaction, any())).thenAnswer(
        (_) async => resultSetOf([
          {'id': 'split-1'},
        ]),
      );

      final result = await buildRepo().update(existing());

      expect(result.valueOrNull?.isShared, isTrue);
    });

    test('entidade marcada sem parte no banco perde a marca', () async {
      final result = await buildRepo().update(
        existing().copyWith(isShared: true),
      );

      expect(result.valueOrNull?.isShared, isFalse);
    });

    test('erro do banco vira DatabaseFailure', () async {
      when(() => db.writeTransaction<void>(any())).thenThrow(
        Exception('conflito'),
      );

      final result = await buildRepo().update(existing());

      expect(
        result.failureOrNull,
        isA<DatabaseFailure>(),
      );
    });
  });

  group('delete', () {
    test('remove por id, e leva as partes junto', () async {
      final result = await buildRepo().delete('tx-1');

      expect(result, isA<Ok<void, Failure>>());
      // As duas escritas, na ordem, dentro da mesma transação: as views do
      // PowerSync não têm FK, então o `on delete cascade` do Postgres não
      // acontece no aparelho. Ver o comentário em `delete`.
      expect(txSql, hasLength(2));
      expect(txSql.first, contains('DELETE FROM expense_splits'));
      expect(txSql.last, contains('DELETE FROM transactions'));
    });

    test('erro do banco vira DatabaseFailure', () async {
      when(() => db.writeTransaction<void>(any())).thenThrow(
        Exception('travou'),
      );

      final result = await buildRepo().delete('tx-1');

      expect(
        result.failureOrNull,
        isA<DatabaseFailure>(),
      );
    });
  });
}
