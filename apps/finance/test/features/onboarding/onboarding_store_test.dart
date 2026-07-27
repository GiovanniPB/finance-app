import 'package:core/core.dart';
import 'package:finance/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:sqlite_async/sqlite_async.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

Row fakeRow(Map<String, Object?> values) => ResultSet(
  values.keys.toList(),
  List.filled(values.length, null),
  [values.values.toList()],
).first;

void main() {
  setUpAll(() => registerFallbackValue(<Object?>[]));

  group('OnboardingStore', () {
    late MockSqliteConnection db;

    OnboardingStore buildStore() => OnboardingStore(db: db);

    setUp(() {
      db = MockSqliteConnection();
      when(() => db.getOptional(any(), any())).thenAnswer((_) async => null);
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());
    });

    test('sem linha gravada, não viu', () async {
      expect(await buildStore().hasSeen(), isFalse);
    });

    test('procura pela chave de onboarding', () async {
      await buildStore().hasSeen();

      final captured = verify(
        () => db.getOptional(captureAny(), captureAny()),
      ).captured;
      expect(captured[0], AppPrefsSql.select);
      expect(captured[1], ['onboarding_seen']);
    });

    test('com a linha gravada, já viu', () async {
      when(
        () => db.getOptional(any(), any()),
      ).thenAnswer((_) async => fakeRow({'value': '1'}));

      expect(await buildStore().hasSeen(), isTrue);
    });

    test('valor diferente de 1 não conta como visto', () async {
      when(
        () => db.getOptional(any(), any()),
      ).thenAnswer((_) async => fakeRow({'value': '0'}));

      expect(await buildStore().hasSeen(), isFalse);
    });

    test('erro de leitura devolve falso em vez de estourar o boot', () async {
      when(() => db.getOptional(any(), any())).thenThrow(Exception('falhou'));

      expect(await buildStore().hasSeen(), isFalse);
    });

    test('markSeen apaga antes de inserir — view não aceita UPSERT', () async {
      final result = await buildStore().markSeen();

      expect(result, isA<Ok<void, Failure>>());
      final captured = verify(
        () => db.execute(captureAny(), captureAny()),
      ).captured;
      expect(captured[0], AppPrefsSql.delete);
      expect(captured[1], ['onboarding_seen']);
      expect(captured[2], AppPrefsSql.insert);
      expect(captured[3], ['onboarding_seen', '1']);
    });

    test('nenhuma statement usa UPSERT', () {
      for (final sql in [
        AppPrefsSql.select,
        AppPrefsSql.delete,
        AppPrefsSql.insert,
      ]) {
        expect(sql, isNot(contains('ON CONFLICT')));
      }
    });

    test('erro de escrita vira DatabaseFailure', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('falhou'));

      expect((await buildStore().markSeen()).failureOrNull, isA<Failure>());
    });
  });

  // Mesmo teste de guarda do orçamento: tabela do PowerSync é view com triggers
  // `INSTEAD OF`, e mock de conexão não distingue SQL válido de SQL recusado.
  // `localOnly` não muda isso — a view existe do mesmo jeito.
  group('SQL de preferências contra uma view como a do PowerSync', () {
    late CommonDatabase db;

    setUp(() {
      db = sqlite3.openInMemory()
        ..execute('CREATE TABLE prefs_data (id TEXT PRIMARY KEY, value TEXT);')
        ..execute('CREATE VIEW app_prefs AS SELECT * FROM prefs_data;')
        ..execute('''
          CREATE TRIGGER prefs_insert INSTEAD OF INSERT ON app_prefs BEGIN
            INSERT INTO prefs_data (id, value) VALUES (new.id, new.value);
          END;
        ''')
        ..execute('''
          CREATE TRIGGER prefs_delete INSTEAD OF DELETE ON app_prefs BEGIN
            DELETE FROM prefs_data WHERE id = old.id;
          END;
        ''');
    });

    tearDown(() => db.close());

    test('gravar duas vezes não duplica nem estoura', () {
      for (var i = 0; i < 2; i++) {
        db
          ..execute(AppPrefsSql.delete, ['onboarding_seen'])
          ..execute(AppPrefsSql.insert, ['onboarding_seen', '1']);
      }

      final rows = db.select(AppPrefsSql.select, ['onboarding_seen']);
      expect(rows, hasLength(1));
      expect(rows.single['value'], '1');
    });

    test('a view recusa UPSERT — o motivo do delete-then-insert', () {
      expect(
        () => db.execute(
          '${AppPrefsSql.insert} ON CONFLICT (id) DO UPDATE SET value = ?',
          ['onboarding_seen', '1', '1'],
        ),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('UPSERT'),
          ),
        ),
      );
    });
  });
}
