import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/budget.dart';

part 'budgets_providers.g.dart';

/// Orçamentos do espaço ativo.
@riverpod
Stream<List<Budget>> budgets(Ref ref) {
  final space = ref.watch(activeSpaceProvider);
  if (space == null) return Stream.value(const []);
  return ref.watch(budgetsRepositoryProvider).watchBySpace(space.id);
}

/// Orçamentos do mês em foco cruzados com o gasto acumulado (RN-1.3).
///
/// Ordena colocando o que precisa de atenção primeiro: estourado, depois perto
/// do limite, depois o resto. A tela não precisa reordenar nada.
@riverpod
List<BudgetUsage> budgetUsage(Ref ref) {
  final all = ref.watch(budgetsProvider).asData?.value ?? const <Budget>[];
  final month = ref.watch(focusedMonthProvider);
  final summary = ref.watch(monthSummaryProvider);

  final usage = [
    for (final budget in all)
      if (_appliesTo(budget, month))
        BudgetUsage(budget: budget, spent: summary.spentIn(budget.categoryId)),
  ]..sort((a, b) => b.ratio.compareTo(a.ratio));

  return List.unmodifiable(usage);
}

/// Se o orçamento vale para o mês em foco.
///
/// Mensal: o orçamento vigente é o mais recente que começou até o fim do mês.
/// Semanal ainda não é filtrado por semana — a UI da Fase 0 só mostra mensal.
bool _appliesTo(Budget budget, DateTime month) {
  if (budget.period != BudgetPeriod.monthly) return false;
  final endOfMonth = DateTime(month.year, month.month + 1);
  return budget.startsAt.isBefore(endOfMonth);
}
