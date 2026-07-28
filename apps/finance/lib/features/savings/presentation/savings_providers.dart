import 'package:core/core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/goal_progress.dart';
import '../domain/savings_badge.dart';
import '../domain/savings_contribution.dart';
import '../domain/savings_goal.dart';
import '../domain/savings_streak.dart';

part 'savings_providers.g.dart';

/// Metas do espaço ativo.
///
/// Emite lista vazia enquanto não há espaço ativo (primeiro boot antes do sync)
/// em vez de travar a UI num carregamento infinito — mesma escolha de
/// `monthTransactionsProvider`.
@riverpod
Stream<List<SavingsGoal>> savingsGoals(Ref ref) {
  final space = ref.watch(activeSpaceProvider);
  if (space == null) return Stream.value(const []);
  return ref.watch(savingsRepositoryProvider).watchGoals(space.id);
}

/// Todas as contribuições do espaço ativo, de todas as metas.
@riverpod
Stream<List<SavingsContribution>> savingsContributions(Ref ref) {
  final space = ref.watch(activeSpaceProvider);
  if (space == null) return Stream.value(const []);
  return ref.watch(savingsRepositoryProvider).watchContributions(space.id);
}

/// Cada meta ativa cruzada com o que já foi guardado nela (RN-3.3).
///
/// A ordem é deliberada: **o que ainda está em andamento vem primeiro**, e o
/// concluído desce. Numa tela de orçamento faz sentido subir o que precisa de
/// atenção; aqui a meta concluída não pede nada de ninguém, e deixá-la no topo
/// empurraria para baixo justamente o que ainda depende de uma ação. Entre as
/// em andamento, a mais próxima de fechar vem antes.
///
/// Meta pausada fica fora: [SavingsGoalStatus.paused] é o usuário dizendo "não
/// me cobre disto agora".
@riverpod
List<GoalProgress> goalProgressList(Ref ref) {
  final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];
  final contributions =
      ref.watch(savingsContributionsProvider).asData?.value ?? const [];
  final month = ref.watch(focusedMonthProvider);
  final income = ref.watch(monthSummaryProvider).income;
  final now = ref.watch(clockProvider)();

  final progress = [
    for (final goal in goals)
      if (goal.status != SavingsGoalStatus.paused)
        GoalProgress.from(
          goal: goal,
          contributions: contributions,
          month: month,
          now: now,
          monthIncome: income,
        ),
  ]..sort(_inProgressFirst);

  return List.unmodifiable(progress);
}

/// Progresso de uma meta específica, para a tela de detalhe.
///
/// Nulo quando a meta não existe mais — é o que acontece na própria tela depois
/// de excluir, e devolver nulo deixa a tela sair em vez de estourar.
@riverpod
GoalProgress? goalProgress(Ref ref, String goalId) {
  final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];
  final goal = goals.where((g) => g.id == goalId).firstOrNull;
  if (goal == null) return null;

  final contributions =
      ref.watch(savingsContributionsProvider).asData?.value ?? const [];

  return GoalProgress.from(
    goal: goal,
    contributions: contributions,
    month: ref.watch(focusedMonthProvider),
    now: ref.watch(clockProvider)(),
    monthIncome: ref.watch(monthSummaryProvider).income,
  );
}

/// Contribuições de uma meta, mais recentes primeiro, **pendentes no topo**.
///
/// O que espera confirmação sobe porque é o único item da lista que pede uma
/// ação; o resto é histórico.
@riverpod
List<SavingsContribution> goalContributions(Ref ref, String goalId) {
  final all = ref.watch(savingsContributionsProvider).asData?.value ?? const [];

  final mine =
      [
        for (final contribution in all)
          if (contribution.goalId == goalId) contribution,
      ]..sort((a, b) {
        if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
        return b.contributedAt.compareTo(a.contributedAt);
      });

  return List.unmodifiable(mine);
}

/// Total guardado em todas as metas ativas, desde sempre.
///
/// Nulo em dois casos, ambos porque um número seria pior que nenhum — mesma
/// regra de `accountsNetBalanceProvider`:
///  • **sem meta alguma**, porque "R$ 0,00" e "nenhuma meta" são estados
/// diferentes, e o segundo tem tela própria;
///  • **moedas misturadas**, porque somar BRL com USD não tem resultado.
@riverpod
Money? savingsTotal(Ref ref) {
  final progress = ref.watch(goalProgressListProvider);
  if (progress.isEmpty) return null;

  final currency = progress.first.goal.currency;
  if (progress.any((p) => p.goal.currency != currency)) return null;

  return progress
      .map((p) => p.lifetimeContributed)
      .reduce((total, amount) => total + amount);
}

/// Quanto foi guardado no mês em foco, somando todas as metas ativas.
///
/// Diferente de [savingsTotalProvider]: aqui a janela é o mês, inclusive para
/// meta por objetivo — a pergunta é "quanto eu guardei em julho", e ela vale
/// para qualquer tipo de meta.
@riverpod
Money savingsMonthTotal(Ref ref) {
  final contributions =
      ref.watch(savingsContributionsProvider).asData?.value ?? const [];
  final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];
  final month = ref.watch(focusedMonthProvider);

  final activeIds = {
    for (final goal in goals)
      if (goal.status != SavingsGoalStatus.paused) goal.id,
  };

  var total = const Money.zero();
  for (final contribution in contributions) {
    if (contribution.isPending) continue;
    if (!activeIds.contains(contribution.goalId)) continue;
    if (contribution.amount.currency != total.currency) continue;

    final local = contribution.contributedAt.toLocal();
    if (local.year != month.year || local.month != month.month) continue;

    total += contribution.amount.abs;
  }
  return total;
}

/// Metas pausadas do espaço.
///
/// Existe porque [goalProgressListProvider] as exclui: sem uma lista própria,
/// pausar uma meta a faria desaparecer da única tela que leva ao detalhe dela —
/// pausar viraria um esconder irreversível.
///
/// Sem progresso calculado, de propósito. Meta pausada não tem ritmo a comparar
/// nem projeção a fazer, e desenhar uma barra seria justamente a cobrança que
/// pausar existe para calar.
@riverpod
List<SavingsGoal> pausedGoals(Ref ref) {
  final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];

  return List.unmodifiable([
    for (final goal in goals)
      if (goal.status == SavingsGoalStatus.paused) goal,
  ]);
}

/// A meta de cada lançamento que financiou uma contribuição, indexada pelo id
/// do lançamento.
///
/// A folha de edição de lançamento consulta este mapa para saber que aquele
/// lançamento não é dela: valor e data pertencem ao evento da meta, e editá-los
/// de um lado só faria as duas faces discordarem.
///
/// O mapa é montado em memória em vez de por query com join porque
/// [savingsContributionsProvider] já traz o espaço inteiro para a tela de
/// Poupança — indexá-lo aqui não lê nenhuma linha nova.
@riverpod
Map<String, SavingsGoal> goalByTransactionId(Ref ref) {
  final contributions =
      ref.watch(savingsContributionsProvider).asData?.value ?? const [];
  final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];

  final goalsById = {for (final goal in goals) goal.id: goal};

  final byTransaction = <String, SavingsGoal>{};
  for (final contribution in contributions) {
    final transactionId = contribution.transactionId;
    final goal = goalsById[contribution.goalId];
    if (transactionId == null || goal == null) continue;
    byTransaction[transactionId] = goal;
  }

  return Map.unmodifiable(byTransaction);
}

/// Quantas contribuições detectadas aguardam confirmação no espaço (RN-3.2).
///
/// Zero em toda a Fase 1 sem Open Finance — só a ingestão da Pluggy cria linha
/// não confirmada. Existe para a tela já saber somar quando isso acontecer.
@riverpod
int pendingContributionsCount(Ref ref) {
  final contributions =
      ref.watch(savingsContributionsProvider).asData?.value ?? const [];
  return contributions.where((c) => c.isPending).length;
}

/// A sequência de semanas com aporte no espaço ativo (RN-3.4).
///
/// Por espaço e não por meta: o streak mede o **hábito de poupar**, e quem
/// guardou toda semana alternando entre duas metas manteve o hábito. Por meta,
/// a mesma pessoa apareceria com duas sequências picotadas.
@riverpod
SavingsStreak savingsStreak(Ref ref) {
  final contributions =
      ref.watch(savingsContributionsProvider).asData?.value ?? const [];

  return SavingsStreak.from(
    contributions: contributions,
    now: ref.watch(clockProvider)(),
  );
}

/// As conquistas do espaço ativo, desbloqueadas primeiro (PRD §8.2).
///
/// **Meta concluída aqui é só a por objetivo.** Meta mensal "conclui" todo mês
/// por desenho — `GoalProgress.isComplete` nela responde pela janela do mês —,
/// e contá-la faria a conquista desbloquear em julho e sumir em 1º de agosto.
/// Numa meta por objetivo o acumulado é da vida toda e só cresce, então o
/// desbloqueio é estável. Meta com status `completed` conta junto, para o dia
/// em que algo passar a marcá-la.
@riverpod
List<BadgeStatus> savingsBadges(Ref ref) {
  final contributions =
      ref.watch(savingsContributionsProvider).asData?.value ?? const [];
  final progress = ref.watch(goalProgressListProvider);

  final completed = progress.where((p) {
    if (p.goal.status == SavingsGoalStatus.completed) return true;
    return !p.goal.type.isMonthly && p.isComplete;
  }).length;

  return deriveBadges(
    contributions: contributions.where((c) => !c.isPending).length,
    totalSaved: ref.watch(savingsTotalProvider),
    bestStreakWeeks: ref.watch(savingsStreakProvider).bestWeeks,
    completedGoals: completed,
  );
}

/// Em andamento antes de concluída; entre as em andamento, a mais adiantada
/// primeiro.
int _inProgressFirst(GoalProgress a, GoalProgress b) {
  if (a.isComplete != b.isComplete) return a.isComplete ? 1 : -1;
  return b.ratio.compareTo(a.ratio);
}
