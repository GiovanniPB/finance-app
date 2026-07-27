import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';

import '../domain/budget.dart';
import '../domain/budgets_repository.dart';

/// Implementação sobre o PowerSync (SQL bruto).
class BudgetsRepositoryImpl implements BudgetsRepository {
  BudgetsRepositoryImpl({
    required this.db,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('BudgetsRepository');

  final SqliteConnection db;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  @override
  Stream<List<Budget>> watchBySpace(String spaceId) => db
      .watch(
        'SELECT * FROM budgets WHERE space_id = ? ORDER BY starts_at DESC',
        parameters: [spaceId],
      )
      .map((results) => results.map(Budget.fromRow).toList());

  @override
  Future<Result<Budget, Failure>> upsert({
    required String spaceId,
    required String categoryId,
    required Money limit,
    required DateTime startsAt,
    BudgetPeriod period = BudgetPeriod.monthly,
  }) async {
    if (!limit.isPositive) {
      return const Err(
        ValidationFailure('O limite do orçamento deve ser maior que zero.'),
      );
    }

    final timestamp = _now();
    final budget = Budget(
      id: _genId(),
      spaceId: spaceId,
      categoryId: categoryId,
      limit: limit,
      period: period,
      startsAt: startsAt,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    try {
      final cols = budget.toColumns();
      // O ON CONFLICT espelha a unique do Postgres: reorçar a mesma
      // categoria/período substitui o limite em vez de duplicar a linha.
      await db.execute(
        'INSERT INTO budgets (id, space_id, category_id, amount_minor, '
        'currency, period, starts_at, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (space_id, category_id, period, starts_at) '
        'DO UPDATE SET amount_minor = excluded.amount_minor, '
        'currency = excluded.currency, updated_at = excluded.updated_at',
        [
          cols['id'],
          cols['space_id'],
          cols['category_id'],
          cols['amount_minor'],
          cols['currency'],
          cols['period'],
          cols['starts_at'],
          cols['created_at'],
          cols['updated_at'],
        ],
      );
      return Ok(budget);
    } on Exception catch (e, st) {
      _log.severe('Falha ao salvar orçamento', e, st);
      return Err(
        DatabaseFailure('Não foi possível salvar o orçamento.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      await db.execute('DELETE FROM budgets WHERE id = ?', [id]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover orçamento', e, st);
      return Err(
        DatabaseFailure('Não foi possível remover o orçamento.', cause: e),
      );
    }
  }
}
