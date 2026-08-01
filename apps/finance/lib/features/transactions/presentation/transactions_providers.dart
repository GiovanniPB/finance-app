import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../domain/month_summary.dart';
import '../domain/transaction.dart';

part 'transactions_providers.g.dart';

/// Mês em foco na UI, normalizado para o primeiro dia às 00:00 local.
///
/// A lista e a home leem daqui; trocar de mês é trocar este estado.
@riverpod
class FocusedMonth extends _$FocusedMonth {
  @override
  DateTime build() {
    // Pelo `clockProvider`, não por `DateTime.now()`: era a única leitura de
    // "hoje" na camada de apresentação que escapava do relógio substituível, e
    // por isso cinco testes de julho de 2026 passaram a falhar em 1º de agosto.
    final now = ref.watch(clockProvider)();
    return DateTime(now.year, now.month);
  }

  /// Vai para o mês anterior.
  void previous() => state = DateTime(state.year, state.month - 1);

  /// Vai para o mês seguinte.
  void next() => state = DateTime(state.year, state.month + 1);

  /// Salta para um mês específico (normalizado para o dia 1).
  void select(DateTime month) => state = DateTime(month.year, month.month);
}

/// Transações do espaço ativo no mês em foco, mais recentes primeiro.
///
/// Emite lista vazia enquanto não há espaço ativo (primeiro boot antes do sync)
/// em vez de travar a UI num estado de carregamento infinito.
@riverpod
Stream<List<Transaction>> monthTransactions(Ref ref) {
  final space = ref.watch(activeSpaceProvider);
  if (space == null) return Stream.value(const []);

  final month = ref.watch(focusedMonthProvider);
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);

  return ref
      .watch(transactionsRepositoryProvider)
      .watchBySpace(space.id, from: from, to: to);
}

/// Resumo do mês derivado das transações já carregadas.
///
/// A regra de agregação mora em [MonthSummary], no domínio — este provider só
/// liga o stream ao cálculo.
@riverpod
MonthSummary monthSummary(Ref ref) {
  final transactions = ref.watch(monthTransactionsProvider).asData?.value;
  if (transactions == null) return MonthSummary.empty;
  return MonthSummary.from(transactions);
}
