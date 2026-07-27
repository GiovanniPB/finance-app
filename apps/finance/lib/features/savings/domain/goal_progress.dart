import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'savings_contribution.dart';
import 'savings_goal.dart';

/// Uma meta cruzada com o que já foi guardado nela (RN-3.3).
///
/// Não é entidade persistida — é o resultado de compor uma [SavingsGoal] com as
/// contribuições dela, como `MonthSummary` faz com transações. Vive no domínio
/// porque as regras que resolve **são** regra de negócio, e por isso são
/// testáveis sem Riverpod e sem banco:
///
///  • **só contribuição confirmada conta** (RN-3.3): o Open Finance propõe, o
///    usuário confirma, e o número grande só se move no sim;
///  • **o alvo depende do tipo** — valor fixo para objetivo, valor do mês para
///    valor fixo mensal, e fatia da renda do mês para percentual;
///  • **a janela depende do tipo** — objetivo acumula para sempre, os mensais
///    recomeçam a cada mês. Sem essa distinção uma meta de R$ 500/mês
///    pareceria concluída para sempre no segundo mês.
@immutable
class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.contributed,
    required this.target,
    required this.month,
    required this.monthIncome,
    required this.pendingCount,
    required this.lifetimeContributed,
    required this.paceRatio,
    required this.now,
  });

  /// Compõe o progresso a partir das contribuições da meta.
  ///
  /// [contributions] pode conter contribuições de outras metas e não
  /// confirmadas — a filtragem é aqui, e não no chamador, para nenhuma tela
  /// conseguir contar o que não deve.
  ///
  /// [monthIncome] só importa em meta percentual: é a renda lançada no mês em
  /// foco, que é a base da fatia (resposta à questão aberta #1 do PRD — a renda
  /// é derivada dos lançamentos `income`, não declarada à parte).
  factory GoalProgress.from({
    required SavingsGoal goal,
    required List<SavingsContribution> contributions,
    required DateTime month,
    required DateTime now,
    Money monthIncome = const Money.zero(),
  }) {
    final mine = contributions.where((c) => c.goalId == goal.id);

    var lifetime = Money.zero(currency: goal.currency);
    var inWindow = Money.zero(currency: goal.currency);
    var pending = 0;

    for (final contribution in mine) {
      if (contribution.isPending) {
        pending++;
        continue;
      }
      // Aporte em outra moeda não é somável e não é convertível aqui. Não
      // acontece hoje (o formulário só cria na moeda da meta), mas somar
      // mesmo assim lançaria e derrubaria a lista inteira por causa de uma
      // linha — ver o débito de moeda no roadmap.
      if (contribution.amount.currency != goal.currency) continue;

      final amount = contribution.amount.abs;
      lifetime += amount;
      if (!goal.isMonthly || _isSameMonth(contribution.contributedAt, month)) {
        inWindow += amount;
      }
    }

    return GoalProgress(
      goal: goal,
      contributed: inWindow,
      target: _targetFor(goal, monthIncome),
      month: month,
      monthIncome: monthIncome,
      pendingCount: pending,
      lifetimeContributed: lifetime,
      paceRatio: _paceRatio(goal, now),
      now: now,
    );
  }

  final SavingsGoal goal;

  /// Quanto já foi guardado **na janela do tipo**: a vida toda numa meta por
  /// objetivo, o mês em foco nas mensais.
  final Money contributed;

  /// O alvo da janela. Zero quando não há base para calcular (meta percentual
  /// num mês sem receita lançada) — ver [needsIncome].
  final Money target;

  /// Mês em foco, que é a janela das metas mensais.
  final DateTime month;

  /// Renda lançada no mês em foco. Base da meta percentual, e a tela mostra de
  /// onde o número saiu em vez de exibir um alvo sem procedência.
  final Money monthIncome;

  /// Contribuições detectadas e ainda não confirmadas (RN-3.2). **Não entram**
  /// em [contributed]; existem para a UI poder pedir o sim.
  final int pendingCount;

  /// Total confirmado desde sempre, independentemente da janela. É a base do
  /// ritmo mensal e do total da tela de Poupança.
  final Money lifetimeContributed;

  /// Fração do prazo já decorrida, de 0 a 1. **Nula quando a meta não tem
  /// prazo** — sem prazo não existe "onde eu deveria estar hoje", e a UI não
  /// desenha a marca de ritmo.
  final double? paceRatio;

  /// "Agora" injetado, para o cálculo ser determinístico em teste.
  final DateTime now;

  /// Se existe alvo calculável. Falso só na meta percentual de um mês sem
  /// receita lançada.
  bool get hasTarget => target.isPositive;

  /// Meta percentual sem base: há um percentual escolhido, mas nenhuma receita
  /// lançada no mês para aplicá-lo. É um estado distinto de "0% guardado", e a
  /// tela precisa dizer isso em vez de mostrar zero.
  bool get needsIncome =>
      goal.type == SavingsGoalType.percentageIncome && !monthIncome.isPositive;

  /// Fração do alvo já guardada. Pode passar de 1 (guardar além do alvo é bom).
  double get ratio {
    if (!hasTarget) return 0;
    return contributed.amountMinor / target.amountMinor;
  }

  /// Percentual inteiro para exibição.
  int get percent => (ratio * 100).round();

  /// Alvo atingido. **Nunca** é um estado de alerta — é o momento de conquista,
  /// e o único preenchimento inteiro da marca no app.
  bool get isComplete => hasTarget && contributed >= target;

  /// Quanto falta. Zero quando o alvo foi atingido (nunca negativo).
  Money get remaining {
    final left = target - contributed;
    return left.isNegative ? Money.zero(currency: left.currency) : left;
  }

  /// Atrasado em relação ao prazo: guardou proporcionalmente menos do que o
  /// tempo já consumido.
  ///
  /// **Não é erro e não vira cor de alarme** — só texto. Uma meta atrasada é
  /// informação, e pintá-la de vermelho é o mesmo equívoco de pintar despesa de
  /// vermelho (ver a doc de `AppTokens`).
  bool get isBehind {
    final pace = paceRatio;
    if (pace == null || isComplete) return false;
    return ratio < pace;
  }

  /// Média guardada por mês desde a criação da meta.
  ///
  /// Conta os meses decorridos, não os meses em que houve aporte: quem guardou
  /// R$ 400 em três meses tem ritmo de R$ 133, não de R$ 400. É o número que
  /// torna a projeção honesta.
  Money get monthlyPace {
    final months = _monthsBetween(goal.createdAt, now) + 1;
    return Money.fromMinor(
      lifetimeContributed.amountMinor ~/ (months < 1 ? 1 : months),
      currency: goal.currency,
    );
  }

  /// Quando a meta fecha **no ritmo atual** (RN-3.3).
  ///
  /// Nula quando não há o que projetar: alvo já atingido, sem alvo, ou ritmo
  /// zero (nunca guardou nada — projetar daria uma data infinita).
  DateTime? get projectedCompletion {
    if (!hasTarget || isComplete) return null;
    final pace = monthlyPace.amountMinor;
    if (pace <= 0) return null;

    final monthsNeeded = (remaining.amountMinor / pace).ceil();
    return DateTime(now.year, now.month + monthsNeeded);
  }

  /// Quanto seria preciso guardar por mês para fechar **no prazo**.
  ///
  /// Nula sem prazo, sem alvo ou com o alvo já atingido. O mês corrente conta
  /// como disponível: prazo neste mês ou já vencido cai em um mês, porque a
  /// alternativa seria dividir por zero e afirmar que é impossível.
  Money? get requiredMonthly {
    final deadline = goal.targetDate;
    if (deadline == null || !hasTarget || isComplete) return null;

    final monthsLeft = _monthsBetween(now, deadline);
    final divisor = monthsLeft < 1 ? 1 : monthsLeft;
    return Money.fromMinor(
      remaining.amountMinor ~/ divisor,
      currency: goal.currency,
    );
  }

  /// Alvo da janela por tipo de meta.
  static Money _targetFor(SavingsGoal goal, Money monthIncome) {
    final currency = goal.currency;
    return switch (goal.type) {
      SavingsGoalType.objective || SavingsGoalType.fixedAmount =>
        goal.targetAmount ?? Money.zero(currency: currency),
      // Trunca em vez de arredondar: 20% de R$ 5.400,01 é R$ 1.080,00 e não
      // R$ 1.080,01 — pedir um centavo a mais do que a conta dá seria estranho
      // num alvo que já é aproximação.
      SavingsGoalType.percentageIncome => Money.fromMinor(
        (monthIncome.abs.amountMinor * (goal.percentage ?? 0)) ~/ 100,
        currency: currency,
      ),
    };
  }

  /// Fração do prazo decorrida. Nula sem prazo.
  static double? _paceRatio(SavingsGoal goal, DateTime now) {
    final deadline = goal.targetDate;
    if (deadline == null) return null;

    final total = deadline.difference(goal.createdAt).inSeconds;
    // Prazo no passado ou no mesmo instante da criação: o tempo acabou.
    if (total <= 0) return 1;

    final elapsed = now.difference(goal.createdAt).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// Mês como número contínuo, para comparar mês a mês em vez de instante a
  /// instante — mesma razão de `_monthOrdinal` em `budgets_providers`.
  static int _monthsBetween(DateTime from, DateTime to) =>
      (to.year * 12 + to.month) - (from.year * 12 + from.month);

  static bool _isSameMonth(DateTime a, DateTime b) {
    // `contributed_at` é `timestamptz`: comparar em local é o que faz "julho"
    // significar julho no fuso do usuário, e não em UTC.
    final local = a.toLocal();
    return local.year == b.year && local.month == b.month;
  }
}
