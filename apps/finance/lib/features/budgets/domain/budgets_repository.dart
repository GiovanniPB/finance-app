import 'package:core/core.dart';

import 'budget.dart';

/// Contrato da camada de dados de orçamentos.
abstract interface class BudgetsRepository {
  /// Stream reativo dos orçamentos de um espaço.
  Stream<List<Budget>> watchBySpace(String spaceId);

  /// Cria ou substitui o orçamento de uma categoria/período/início.
  ///
  /// A unicidade é garantida no banco por
  /// `unique (space_id, category_id, period, starts_at)`.
  Future<Result<Budget, Failure>> upsert({
    required String spaceId,
    required String categoryId,
    required Money limit,
    required DateTime startsAt,
    BudgetPeriod period = BudgetPeriod.monthly,
  });

  /// Remove um orçamento pelo id.
  Future<Result<void, Failure>> delete(String id);
}
