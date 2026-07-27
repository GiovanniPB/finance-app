import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';

import '../domain/budget.dart';
import '../domain/budgets_repository.dart';

/// Statements de orçamento, em constantes para o teste de guarda rodá-las
/// contra uma view igual à que o PowerSync cria.
///
/// **Por que não há UPSERT aqui.** No Postgres, `budgets` tem
/// `unique (space_id, category_id, period, starts_at)` e um `ON CONFLICT`
/// resolveria o reorçamento numa statement só. Localmente não: as tabelas do
/// PowerSync são **views com triggers `INSTEAD OF`**, e o SQLite recusa com
/// `cannot UPSERT a view`. Daí o select-then-write — a unicidade continua
/// garantida no servidor, que é onde ela vale contra escrita concorrente.
abstract final class BudgetSql {
  /// Busca o orçamento do período pela chave de negócio, não pelo id.
  static const selectExisting =
      'SELECT id, created_at FROM budgets '
      'WHERE space_id = ? AND category_id = ? AND period = ? '
      'AND starts_at = ? LIMIT 1';

  static const insert =
      'INSERT INTO budgets (id, space_id, category_id, amount_minor, '
      'currency, period, starts_at, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)';

  /// Só limite e moeda mudam: período, categoria e início são a identidade.
  static const update =
      'UPDATE budgets SET amount_minor = ?, currency = ?, updated_at = ? '
      'WHERE id = ?';

  static const deleteById = 'DELETE FROM budgets WHERE id = ?';

  static const watchBySpace =
      'SELECT * FROM budgets WHERE space_id = ? ORDER BY starts_at DESC';
}

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
      .watch(BudgetSql.watchBySpace, parameters: [spaceId])
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

    try {
      final existing = await db.getOptional(BudgetSql.selectExisting, [
        spaceId,
        categoryId,
        period.db,
        Budget.dateOnly(startsAt),
      ]);

      if (existing != null) {
        // Reorçar o mesmo período substitui o limite: mantém o id e a data de
        // criação original, em vez de duplicar a linha.
        final budget = Budget(
          id: existing['id'] as String,
          spaceId: spaceId,
          categoryId: categoryId,
          limit: limit,
          period: period,
          startsAt: startsAt,
          createdAt: DateTime.parse(existing['created_at'] as String),
          updatedAt: timestamp,
        );
        await db.execute(BudgetSql.update, [
          limit.amountMinor,
          limit.currency,
          timestamp.toIso8601String(),
          budget.id,
        ]);
        return Ok(budget);
      }

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
      final cols = budget.toColumns();
      await db.execute(BudgetSql.insert, [
        cols['id'],
        cols['space_id'],
        cols['category_id'],
        cols['amount_minor'],
        cols['currency'],
        cols['period'],
        cols['starts_at'],
        cols['created_at'],
        cols['updated_at'],
      ]);
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
      await db.execute(BudgetSql.deleteById, [id]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover orçamento', e, st);
      return Err(
        DatabaseFailure('Não foi possível remover o orçamento.', cause: e),
      );
    }
  }
}
