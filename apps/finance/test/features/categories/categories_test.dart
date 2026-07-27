import 'package:core/core.dart';
import 'package:finance/features/categories/data/categories_repository_impl.dart';
import 'package:finance/features/categories/domain/category.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

void main() {
  setUpAll(() => registerFallbackValue(<Object?>[]));

  Map<String, Object?> row({
    String? spaceId,
    int isSystem = 1,
    int? colorIndex = 0,
    String? parentId,
  }) => {
    'id': 'cat-1',
    'space_id': spaceId,
    'name': 'Alimentação',
    'icon_key': 'food',
    'color_index': colorIndex,
    'is_system': isSystem,
    'parent_category_id': parentId,
    'created_at': '2026-07-27T12:00:00.000Z',
    'updated_at': '2026-07-27T12:00:00.000Z',
  };

  group('Category.fromRow', () {
    test('mapeia categoria de sistema (global)', () {
      final category = Category.fromRow(row());

      expect(category.isSystem, isTrue);
      expect(category.spaceId, isNull);
      expect(category.name, 'Alimentação');
      expect(category.iconKey, 'food');
      expect(category.colorIndex, 0);
    });

    test('mapeia categoria de usuário (com espaço)', () {
      final category = Category.fromRow(row(spaceId: 'space-1', isSystem: 0));

      expect(category.isSystem, isFalse);
      expect(category.spaceId, 'space-1');
    });

    test('booleano vem como inteiro do PowerSync', () {
      expect(Category.fromRow(row(isSystem: 0)).isSystem, isFalse);
      // O helper usa 1 como padrão.
      expect(Category.fromRow(row()).isSystem, isTrue);
    });

    test('color_index nulo é aceito (design system deriva do hash)', () {
      expect(Category.fromRow(row(colorIndex: null)).colorIndex, isNull);
    });

    test('isChild identifica subcategoria', () {
      expect(Category.fromRow(row()).isChild, isFalse);
      expect(Category.fromRow(row(parentId: 'cat-0')).isChild, isTrue);
    });
  });

  group('Category.toColumns', () {
    test('booleano volta a inteiro', () {
      expect(Category.fromRow(row()).toColumns()['is_system'], 1);
      expect(Category.fromRow(row(isSystem: 0)).toColumns()['is_system'], 0);
    });

    test('round-trip preserva a entidade', () {
      final original = Category.fromRow(row(spaceId: 'space-1', isSystem: 0));

      expect(Category.fromRow(original.toColumns()), original);
    });
  });

  group('CategoriesRepositoryImpl', () {
    late MockSqliteConnection db;

    CategoriesRepositoryImpl buildRepo() => CategoriesRepositoryImpl(
      db: db,
      now: () => DateTime.utc(2026, 7, 27, 12),
      genId: () => 'cat-new',
    );

    setUp(() {
      db = MockSqliteConnection();
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(emptyResultSet()));
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());
    });

    test('watchForSpace inclui as de sistema e as do espaço', () {
      buildRepo().watchForSpace('space-1');

      final captured = verify(
        () => db.watch(
          captureAny(),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      final sql = captured[0] as String;
      expect(sql, contains('is_system = 1'));
      expect(sql, contains('space_id = ?'));
      expect(captured[1], ['space-1']);
    });

    test('watchForSpace lista as de sistema primeiro', () {
      buildRepo().watchForSpace('space-1');

      final sql =
          verify(
                () => db.watch(
                  captureAny(),
                  parameters: any(named: 'parameters'),
                ),
              ).captured.single
              as String;
      expect(sql, contains('ORDER BY is_system DESC'));
    });

    test('create grava categoria de usuário, nunca de sistema', () async {
      final result = await buildRepo().create(
        spaceId: 'space-1',
        name: 'Pet',
        iconKey: 'other',
      );

      final category = result.valueOrNull;
      expect(category, isNotNull);
      expect(category!.isSystem, isFalse);
      expect(category.spaceId, 'space-1');

      final params =
          verify(() => db.execute(any(), captureAny())).captured.single
              as List<Object?>;
      expect(params, contains(0), reason: 'is_system deve ir como 0');
    });

    test('create apara espaços do nome', () async {
      final result = await buildRepo().create(
        spaceId: 'space-1',
        name: '  Pet  ',
        iconKey: 'other',
      );

      expect(result.valueOrNull?.name, 'Pet');
    });

    test('create rejeita nome vazio', () async {
      final result = await buildRepo().create(
        spaceId: 'space-1',
        name: '   ',
        iconKey: 'other',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(any(), any()));
    });

    test('create converte erro do banco em DatabaseFailure', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('falhou'));

      final result = await buildRepo().create(
        spaceId: 'space-1',
        name: 'Pet',
        iconKey: 'other',
      );

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });

    test('delete protege categoria de sistema no SQL', () async {
      await buildRepo().delete('cat-1');

      final sql =
          verify(() => db.execute(captureAny(), any())).captured.single
              as String;
      // A RLS já bloqueia no servidor; a guarda local evita divergência até o
      // próximo sync.
      expect(sql, contains('is_system = 0'));
    });

    test('delete converte erro do banco em DatabaseFailure', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('falhou'));

      expect(
        (await buildRepo().delete('cat-1')).failureOrNull,
        isA<DatabaseFailure>(),
      );
    });
  });
}
