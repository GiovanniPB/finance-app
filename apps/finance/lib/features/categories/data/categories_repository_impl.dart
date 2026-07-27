import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';

import '../domain/categories_repository.dart';
import '../domain/category.dart';

/// Implementação sobre o PowerSync (SQL bruto).
class CategoriesRepositoryImpl implements CategoriesRepository {
  CategoriesRepositoryImpl({
    required this.db,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('CategoriesRepository');

  final SqliteConnection db;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  @override
  Stream<List<Category>> watchForSpace(String spaceId) => db
      .watch(
        // As de sistema são globais (space_id nulo) e valem para todo espaço.
        'SELECT * FROM categories WHERE is_system = 1 OR space_id = ? '
        'ORDER BY is_system DESC, name',
        parameters: [spaceId],
      )
      .map((results) => results.map(Category.fromRow).toList());

  @override
  Future<Result<Category, Failure>> create({
    required String spaceId,
    required String name,
    required String iconKey,
    int? colorIndex,
    String? parentCategoryId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Err(ValidationFailure('Informe um nome para a categoria.'));
    }

    final timestamp = _now();
    final category = Category(
      id: _genId(),
      name: trimmed,
      iconKey: iconKey,
      isSystem: false,
      createdAt: timestamp,
      updatedAt: timestamp,
      spaceId: spaceId,
      colorIndex: colorIndex,
      parentCategoryId: parentCategoryId,
    );

    try {
      final cols = category.toColumns();
      await db.execute(
        'INSERT INTO categories (id, space_id, name, icon_key, color_index, '
        'is_system, parent_category_id, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          cols['id'],
          cols['space_id'],
          cols['name'],
          cols['icon_key'],
          cols['color_index'],
          cols['is_system'],
          cols['parent_category_id'],
          cols['created_at'],
          cols['updated_at'],
        ],
      );
      return Ok(category);
    } on Exception catch (e, st) {
      _log.severe('Falha ao criar categoria', e, st);
      return Err(
        DatabaseFailure('Não foi possível criar a categoria.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      // Guarda local: a RLS já bloqueia no servidor, mas apagar localmente uma
      // categoria de sistema criaria divergência até o próximo sync.
      await db.execute(
        'DELETE FROM categories WHERE id = ? AND is_system = 0',
        [id],
      );
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover categoria', e, st);
      return Err(
        DatabaseFailure('Não foi possível remover a categoria.', cause: e),
      );
    }
  }
}
