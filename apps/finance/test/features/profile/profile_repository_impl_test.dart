import 'package:core/core.dart';
import 'package:finance/features/profile/data/profile_repository_impl.dart';
import 'package:finance/features/profile/domain/profile.dart';
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

/// `getOptional` devolve `Row` (tipo do sqlite3), não um `Map`.
Row rowFrom(Map<String, Object?> values) =>
    ResultSet(values.keys.toList(), const [], [
      values.values.toList(),
    ]).first;

void main() {
  setUpAll(() => registerFallbackValue(<Object?>[]));

  /// O relógio do repositório é fixo, então o parâmetro de `updated_at` é
  /// conhecido. Escrever o valor em vez de `any()` não é preciosismo: um
  /// `any()` **dentro** de uma lista de argumentos vaza o matcher para o
  /// estado global do mocktail e derruba os testes seguintes.
  const iso = '2026-08-01T12:00:00.000Z';

  late MockSqliteConnection db;
  late MockSupabaseClient supabase;
  late MockGoTrueClient auth;

  ProfileRepositoryImpl buildRepo() => ProfileRepositoryImpl(
    db: db,
    supabase: supabase,
    now: () => DateTime.utc(2026, 8, 1, 12),
  );

  void signedIn({String id = 'user-1'}) {
    final user = MockUser();
    when(() => user.id).thenReturn(id);
    when(() => auth.currentUser).thenReturn(user);
  }

  /// O perfil existe no banco local (chegou pelo bucket `user_owned`).
  void profileExists({String? displayName}) {
    when(
      () => db.getOptional(ProfileSql.byId, any()),
    ).thenAnswer(
      (_) async => rowFrom({'id': 'user-1', 'display_name': displayName}),
    );
  }

  setUp(() {
    db = MockSqliteConnection();
    supabase = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(null);
    when(
      () => db.execute(any(), any()),
    ).thenAnswer((_) async => emptyResultSet());
  });

  group('Profile.fromRow', () {
    test('lê nome nulo como "sem nome"', () {
      final profile = Profile.fromRow({
        'id': 'user-1',
        'display_name': null,
      });

      expect(profile.displayName, isNull);
      expect(profile.hasName, isFalse);
    });

    test('lê nome definido', () {
      final profile = Profile.fromRow({
        'id': 'user-1',
        'display_name': 'Giovanni',
      });

      expect(profile.displayName, 'Giovanni');
      expect(profile.hasName, isTrue);
    });
  });

  group('watchMine', () {
    test('sem sessão, emite null sem tocar no banco', () async {
      await expectLater(buildRepo().watchMine(), emits(isNull));
      verifyNever(() => db.watch(any(), parameters: any(named: 'parameters')));
    });

    test('emite o perfil da linha e filtra pelo id da sessão', () async {
      signedIn();
      when(
        () => db.watch(ProfileSql.byId, parameters: ['user-1']),
      ).thenAnswer(
        (_) => Stream.value(
          ResultSet(
            const ['id', 'display_name'],
            const [],
            [
              const ['user-1', 'Giovanni'],
            ],
          ),
        ),
      );

      await expectLater(
        buildRepo().watchMine(),
        emits(isA<Profile>().having((p) => p.displayName, 'nome', 'Giovanni')),
      );
    });

    test('linha ainda não sincronizada emite null', () async {
      signedIn();
      when(
        () => db.watch(ProfileSql.byId, parameters: ['user-1']),
      ).thenAnswer((_) => Stream.value(emptyResultSet()));

      await expectLater(buildRepo().watchMine(), emits(isNull));
    });
  });

  group('updateDisplayName', () {
    test('grava o nome sem espaço nas pontas', () async {
      signedIn();
      profileExists();

      final result = await buildRepo().updateDisplayName('  Giovanni  ');

      expect(result.isOk, isTrue);
      verify(
        () => db.execute(ProfileSql.updateDisplayName, [
          'Giovanni',
          '2026-08-01T12:00:00.000Z',
          'user-1',
        ]),
      ).called(1);
    });

    test('aceita nome de um caractere', () async {
      signedIn();
      profileExists();

      expect((await buildRepo().updateDisplayName('G')).isOk, isTrue);
    });

    test('aceita acento e emoji inteiros', () async {
      signedIn();
      profileExists();

      final result = await buildRepo().updateDisplayName('Ana Antônia 🌱');

      expect(result.isOk, isTrue);
      verify(
        () => db.execute(ProfileSql.updateDisplayName, [
          'Ana Antônia 🌱',
          iso,
          'user-1',
        ]),
      ).called(1);
    });

    test('aceita exatamente 120 caracteres', () async {
      signedIn();
      profileExists();

      final result = await buildRepo().updateDisplayName('a' * 120);

      expect(result.isOk, isTrue);
    });

    test('recusa 121 caracteres sem escrever', () async {
      signedIn();
      profileExists();

      final result = await buildRepo().updateDisplayName('a' * 121);

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(ProfileSql.updateDisplayName, any()));
    });

    test('recusa nome vazio sem escrever', () async {
      signedIn();
      profileExists();

      final result = await buildRepo().updateDisplayName('');

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(ProfileSql.updateDisplayName, any()));
    });

    test('recusa nome só de espaços sem escrever', () async {
      signedIn();
      profileExists();

      final result = await buildRepo().updateDisplayName('     ');

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(ProfileSql.updateDisplayName, any()));
    });

    test('sem sessão, devolve AuthFailure', () async {
      final result = await buildRepo().updateDisplayName('Giovanni');

      expect(result.failureOrNull, isA<AuthFailure>());
      verifyNever(() => db.execute(ProfileSql.updateDisplayName, any()));
    });

    // O caso que o UPDATE silencioso esconde: sem linha, `UPDATE` afeta zero e
    // não levanta nada. Sem a checagem de existência, isto seria um `Ok`.
    test(
      'perfil ainda não sincronizado devolve erro em vez de fingir',
      () async {
        signedIn();
        when(
          () => db.getOptional(ProfileSql.byId, any()),
        ).thenAnswer((_) async => null);

        final result = await buildRepo().updateDisplayName('Giovanni');

        expect(result.failureOrNull, isA<DatabaseFailure>());
        verifyNever(() => db.execute(ProfileSql.updateDisplayName, any()));
      },
    );

    test('falha do banco vira DatabaseFailure, sem vazar exception', () async {
      signedIn();
      profileExists();
      when(
        () => db.execute(ProfileSql.updateDisplayName, any()),
      ).thenThrow(Exception('disco cheio'));

      final result = await buildRepo().updateDisplayName('Giovanni');

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });

    test('a segunda troca vence', () async {
      signedIn();
      profileExists();
      final repo = buildRepo();

      await repo.updateDisplayName('Primeiro');
      await repo.updateDisplayName('Segundo');

      verify(
        () => db.execute(ProfileSql.updateDisplayName, [
          'Segundo',
          iso,
          'user-1',
        ]),
      ).called(1);
      verify(
        () => db.execute(ProfileSql.updateDisplayName, [
          'Primeiro',
          iso,
          'user-1',
        ]),
      ).called(1);
    });
  });
}
