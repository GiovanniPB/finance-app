import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/domain/space.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../domain/expense_split.dart';
import '../domain/month_summary.dart';
import '../domain/settlement.dart';
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

/// As partes de um lançamento dividido (RN-2.1).
///
/// Lista vazia = não dividido. É o que a seção "Dividido entre" lê para decidir
/// entre oferecer "Dividir igualmente" e mostrar o rateio.
@riverpod
Stream<List<ExpenseSplit>> transactionSplits(Ref ref, String transactionId) =>
    ref.watch(transactionsRepositoryProvider).watchSplits(transactionId);

/// O "quem deve a quem" de um espaço (RN-2.2).
///
/// Recebe o espaço por argumento em vez de ler o ativo: a seção mora no
/// **detalhe** de um espaço, que não é necessariamente o que está ativo na
/// bottom nav.
@riverpod
Stream<Settlement> settlement(Ref ref, String spaceId) =>
    ref.watch(settlementRepositoryProvider).watch(spaceId);

/// Este lançamento pode ser dividido?
///
/// As três recusas juntas, porque a tela precisa da resposta única — e porque
/// espalhá-las pela árvore de widgets é como um controle desabilitado aparece
/// num caso que ninguém previu. Espelha o que `splitEqually` recusa na camada
/// `data`: lá é a rede, aqui é a tela.
@riverpod
bool canSplit(Ref ref, Transaction transaction) {
  // Só despesa: receita, transferência e poupança não se rateiam.
  if (transaction.type != TransactionType.expense) return false;

  // Só `group`. `household` é transparência total (PRD §4.2), onde o dinheiro é
  // comum e "quem deve a quem" não é a pergunta; `personal` não tem outro
  // membro.
  final space = ref.watch(spaceByIdProvider(transaction.spaceId)).asData?.value;
  return space?.type == SpaceType.group;
}
