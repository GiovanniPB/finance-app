import 'package:core/core.dart';
import 'package:finance/features/accounts/data/accounts_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
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

  group('watchAll', () {
    test('mapeia linhas do PowerSync para Account', () async {
      final rs = ResultSet(
        ['id', 'owner_id', 'name', 'currency', 'created_at', 'updated_at'],
        List<String?>.filled(6, null),
        [
          [
            'acc-1',
            'user-1',
            'Carteira',
            'BRL',
            '2026-07-14T12:00:00.000Z',
            '2026-07-14T12:00:00.000Z',
          ],
        ],
      );
      when(() => db.watch(any())).thenAnswer((_) => Stream.value(rs));

      final accounts = await buildRepo().watchAll().first;
      expect(accounts, hasLength(1));
      expect(accounts.single.name, 'Carteira');
      expect(accounts.single.ownerId, 'user-1');
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
}
