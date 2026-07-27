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
    for (final budget in _currentPerCategory(all, month))
      BudgetUsage(budget: budget, spent: summary.spentIn(budget.categoryId)),
  ]..sort((a, b) => b.ratio.compareTo(a.ratio));

  return List.unmodifiable(usage);
}

/// Um orçamento por categoria: o vigente no mês em foco.
///
/// Reorçar uma categoria grava **uma linha nova** com `starts_at` no mês da
/// mudança, preservando o limite dos meses anteriores. Sem esta redução a mesma
/// categoria apareceria uma vez por linha histórica.
Iterable<Budget> _currentPerCategory(List<Budget> all, DateTime month) {
  final current = <String, Budget>{};
  for (final budget in all) {
    if (!_appliesTo(budget, month)) continue;
    final vigente = current[budget.categoryId];
    if (vigente == null ||
        _monthOrdinal(budget.startsAt) > _monthOrdinal(vigente.startsAt)) {
      current[budget.categoryId] = budget;
    }
  }
  return current.values;
}

/// Se o orçamento vale para o mês em foco.
///
/// Mensal: o orçamento vigente é o mais recente que começou até o fim do mês.
/// Semanal ainda não é filtrado por semana — a UI da Fase 0 só mostra mensal.
bool _appliesTo(Budget budget, DateTime month) {
  if (budget.period != BudgetPeriod.monthly) return false;
  return _monthOrdinal(budget.startsAt) <= _monthOrdinal(month);
}

/// Mês como número contínuo, para comparar mês a mês em vez de instante a
/// instante.
///
/// `starts_at` é `date` no banco: um orçamento que começa em 1º de julho em UTC
/// é 30 de junho às 21h no fuso de Brasília, e comparar `DateTime` cru o faria
/// vazar para junho.
int _monthOrdinal(DateTime value) => value.year * 12 + value.month;
