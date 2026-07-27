import 'package:core/core.dart';
import 'package:finance/features/transactions/data/transactions_repository_impl.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

void main() {
  setUpAll(() => registerFallbackValue(<Object?>[]));

  late MockSqliteConnection db;
  late MockSupabaseClient supabase;
  late MockGoTrueClient auth;

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
    supabase = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => supabase.auth).thenReturn(auth);
    when(
      () => db.watch(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((_) => Stream.value(emptyResultSet()));
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
      expect(sql, contains('occurred_at >= ?'));
      expect(sql, contains('occurred_at < ?'));
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
      stubExecute();

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

    test('erro do banco vira DatabaseFailure', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('conflito'));

      final result = await buildRepo().update(existing());

      expect(
        result.failureOrNull,
        isA<DatabaseFailure>(),
      );
    });
  });

  group('delete', () {
    test('remove por id', () async {
      stubExecute();

      final result = await buildRepo().delete('tx-1');

      expect(result, isA<Ok<void, Failure>>());
      final params =
          verify(
                () => db.execute(any(), captureAny()),
              ).captured.single
              as List<Object?>;
      expect(params, ['tx-1']);
    });

    test('erro do banco vira DatabaseFailure', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('travou'));

      final result = await buildRepo().delete('tx-1');

      expect(
        result.failureOrNull,
        isA<DatabaseFailure>(),
      );
    });
  });
}
