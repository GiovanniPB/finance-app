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

    /// Faz o `countUsage` responder [total] lançamentos.
    ///
    /// `getAll` devolve `ResultSet`, e não lista de mapas: é a forma que o
    /// SQLite entrega, com nomes de coluna à parte das linhas.
    void usedBy(int total) {
      when(() => db.getAll(any(), any())).thenAnswer(
        (_) async => ResultSet(const ['total'], const [null], [
          [total],
        ]),
      );
    }

    setUp(() {
      db = MockSqliteConnection();
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(emptyResultSet()));
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());
      // `delete` consulta o uso antes de apagar; sem o stub ele nem chega ao
      // DELETE.
      usedBy(0);
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

    test('delete recusa categoria em uso, sem tocar no banco', () async {
      usedBy(3);

      final result = await buildRepo().delete('cat-1');

      // Recusa explícita, e não um DELETE que não apaga nada: o no-op
      // silencioso deixaria a tela fechar como se tivesse dado certo.
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull!.message, contains('3 lançamentos'));
      verifyNever(() => db.execute(any(), any()));
    });

    test('a recusa concorda em número com o singular', () async {
      usedBy(1);

      final result = await buildRepo().delete('cat-1');

      expect(result.failureOrNull!.message, startsWith('Um lançamento usa'));
    });

    test('countUsage conta lançamentos da categoria em qualquer mês', () async {
      usedBy(12);

      expect((await buildRepo().countUsage('cat-1')).valueOrNull, 12);

      final sql =
          verify(() => db.getAll(captureAny(), any())).captured.single
              as String;
      // Sem janela de data: a pergunta é "alguém usa", não "usou este mês".
      expect(sql, contains('FROM transactions WHERE category_id = ?'));
      expect(sql, isNot(contains('occurred_at')));
    });

    test('update grava nome, ícone e cor, e protege a de sistema', () async {
      final category = Category.fromRow(row(spaceId: 'space-1', isSystem: 0));

      final result = await buildRepo().update(
        category.copyWith(
          name: '  Mercado  ',
          iconKey: 'health',
          colorIndex: 3,
        ),
      );

      expect(result.valueOrNull!.name, 'Mercado');

      final captured = verify(
        () => db.execute(captureAny(), captureAny()),
      ).captured;
      final sql = captured.first as String;
      expect(sql, contains('UPDATE categories SET'));
      // Mesma guarda do delete: a linha pode ter mudado por baixo do cliente.
      expect(sql, contains('is_system = 0'));
      // `space_id`, `is_system` e `created_at` são identidade, não dado
      // editável.
      expect(sql, isNot(contains('space_id =')));
      expect(sql, isNot(contains('created_at =')));

      final params = captured[1] as List<Object?>;
      expect(params, contains('Mercado'));
      expect(params, contains('health'));
      expect(params, contains(3));
    });

    test('update recusa categoria de sistema antes do banco', () async {
      final result = await buildRepo().update(Category.fromRow(row()));

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(any(), any()));
    });

    test('update recusa nome vazio', () async {
      final category = Category.fromRow(row(spaceId: 'space-1', isSystem: 0));

      final result = await buildRepo().update(category.copyWith(name: '   '));

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(any(), any()));
    });
  });
}
