import 'package:core/core.dart';

import '../domain/goal_progress.dart';
import '../domain/savings_goal.dart';

/// Texto das metas, num lugar só.
///
/// A lista e o detalhe descrevem o **mesmo** progresso. Duplicar as frases nas
/// duas telas é como elas passam a discordar — foi assim que a linha de
/// transação chegou a dizer "Alimentação / Alimentação". Aqui a frase é
/// derivada do estado, e as duas telas leem daqui.
///
/// Todas as funções recebem o [GoalProgress] inteiro, e não campos soltos:
/// escolher a frase depende de combinações de estado (tipo, prazo, alvo
/// atingido, sem base de renda), e passar campos avulsos convidaria cada tela a
/// recombiná-los do seu jeito.
abstract final class GoalCopy {
  /// O alvo, ao lado do acumulado: "de R$ 8.000,00" ou "de R$ 1.080,00 ·
  /// julho".
  ///
  /// O rótulo do mês só aparece em meta mensal, porque é ali que ele distingue
  /// algo: numa meta por objetivo o acumulado é da vida toda, e dizer "julho"
  /// sugeriria que o número zera no mês seguinte.
  static String target(GoalProgress progress) {
    if (progress.needsIncome) return 'sem base neste mês';

    final target = progress.target.format();
    if (!progress.goal.isMonthly) return 'de $target';
    return 'de $target · ${monthLabel(progress.month, today: progress.now)}';
  }

  /// A linha de status embaixo da barra.
  ///
  /// **Nunca é uma advertência.** Meta atrasada recebe uma frase factual do que
  /// falta, não cor de alarme: pintar atraso de vermelho é o mesmo equívoco de
  /// pintar despesa de vermelho (ver a doc de `AppTokens`).
  static String status(GoalProgress progress) {
    final month = monthLabel(progress.month, today: progress.now);

    if (progress.needsIncome) {
      return 'Nenhuma receita lançada em $month, então ainda não há base para '
          'calcular ${progress.goal.percentage}%.';
    }

    if (progress.isComplete) {
      return progress.goal.isMonthly
          ? '${_capitalize(month)} fechado · recomeça no mês que vem'
          : 'Meta atingida';
    }

    if (progress.goal.type == SavingsGoalType.percentageIncome) {
      return '${progress.goal.percentage}% de '
          '${progress.monthIncome.format()} lançados como receita em $month';
    }

    final missing = 'Faltam ${progress.remaining.format()}';
    final deadline = progress.goal.targetDate;
    if (deadline == null) return missing;

    final until = monthLabel(
      DateTime(deadline.year, deadline.month),
      today: progress.now,
    );
    return '$missing · até $until';
  }

  /// Explica a marca de ritmo, no detalhe. Nula quando não há prazo.
  static String? pace(GoalProgress progress) {
    final pace = progress.paceRatio;
    if (pace == null) return null;

    final expected = (pace * 100).round();
    if (progress.isComplete) return 'Alvo atingido antes do prazo';

    return progress.isBehind
        ? 'No ritmo do prazo você estaria em $expected%'
        : 'Adiantado · o ritmo do prazo pedia $expected%';
  }

  /// A projeção do detalhe (RN-3.3), em prosa.
  ///
  /// Prosa em vez de gráfico de propósito: a pergunta é "chego no prazo?", e
  /// uma frase responde isso melhor que uma curva — sobretudo porque a resposta
  /// interessante é o segundo período, o que dizer quanto guardar por mês.
  ///
  /// Nula quando não há o que projetar: sem alvo, alvo já atingido, ou nunca
  /// houve aporte (ritmo zero projetaria uma data infinita).
  static String? projection(GoalProgress progress) {
    final projected = progress.projectedCompletion;
    if (projected == null) return null;

    final pace = progress.monthlyPace.format();
    final target = progress.target.format();
    final when = monthLabel(projected, today: progress.now);

    final base =
        'Você guardou $pace por mês desde que criou a meta. Nesse ritmo, '
        'chega aos $target em $when';

    final deadline = progress.goal.targetDate;
    if (deadline == null) return '$base.';

    final deadlineMonth = DateTime(deadline.year, deadline.month);
    final months =
        (projected.year * 12 + projected.month) -
        (deadlineMonth.year * 12 + deadlineMonth.month);

    if (months <= 0) return '$base — dentro do prazo.';
    return '$base — ${_plural(months, 'mês', 'meses')} depois do alvo.';
  }

  /// O que seria preciso guardar por mês para fechar no prazo. Nula sem prazo.
  static String? requiredMonthly(GoalProgress progress) {
    final required = progress.requiredMonthly;
    final deadline = progress.goal.targetDate;
    if (required == null || deadline == null) return null;

    final when = monthLabel(
      DateTime(deadline.year, deadline.month),
      today: progress.now,
    );
    return 'Para fechar em $when, seriam ${required.format()} por mês.';
  }

  static String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  static String _plural(int count, String one, String many) =>
      count == 1 ? '1 $one' : '$count $many';
}
