import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// O que uma conquista mede.
///
/// Quatro métricas em vez de uma condição livre por conquista: com uma função
/// por badge, cada uma escolheria sua própria janela e seu próprio critério de
/// "confirmada", e a lista inteira viraria N regras para conferir uma a uma.
/// Assim a regra é `métrica >= limiar`, e o que muda entre badges é só o par.
enum BadgeMetric {
  /// Quantos aportes **confirmados** existem.
  contributions,

  /// Total guardado, em unidades mínimas.
  totalSaved,

  /// A maior sequência de semanas já alcançada (RN-3.4).
  streakWeeks,

  /// Quantas metas atingiram o alvo.
  completedGoals,
}

/// As conquistas básicas do Pilar 3 (PRD §8.2).
///
/// ─────────────────────────────────────────────────────────────────────────
/// DERIVADAS, SEM TABELA — E O QUE ISSO CUSTA
///
/// O PRD modela `achievements (badge_key, earned_at)`. Aqui elas são
/// **derivadas** do histórico, seguindo o [ADR 0007](../../../../../docs/adr/0007-agregado-derivado-vs-coluna.md):
/// duas réplicas offline com as mesmas contribuições desbloqueiam exatamente as
/// mesmas conquistas, então não é coluna. Nenhuma migration nesta fatia.
///
/// **O custo é real e está aceito:** excluir a contribuição que cruzou o
/// limiar faz a conquista voltar a ficar bloqueada. Isso é coerente (o dinheiro
/// não foi guardado, afinal), e é defensável enquanto a conquista vive só
/// dentro do app.
///
/// Deixa de ser defensável na **Fase 3**, quando o feed publicar "fulano
/// desbloqueou uma conquista": evento publicado é fato, não derivação, e não dá
/// para despublicar. É aí que `achievements` com `earned_at` passa a ser
/// necessária — não como cache do que se calcula, mas como registro de que a
/// conquista **foi anunciada**. Está anotado no roadmap.
enum SavingsBadge {
  primeiroAporte(
    key: 'primeiro_aporte',
    label: 'Primeiro passo',
    metric: BadgeMetric.contributions,
    threshold: 1,
    criterion: 'Guardar dinheiro pela primeira vez',
  ),
  cemGuardados(
    key: 'cem_guardados',
    label: r'Primeiros R$ 100',
    metric: BadgeMetric.totalSaved,
    threshold: 10000,
    criterion: r'Acumular R$ 100 guardados',
  ),
  milGuardados(
    key: 'mil_guardados',
    label: r'R$ 1.000',
    metric: BadgeMetric.totalSaved,
    threshold: 100000,
    criterion: r'Acumular R$ 1.000 guardados',
  ),
  dezMilGuardados(
    key: 'dez_mil_guardados',
    label: r'R$ 10.000',
    metric: BadgeMetric.totalSaved,
    threshold: 1000000,
    criterion: r'Acumular R$ 10.000 guardados',
  ),
  quatroSemanas(
    key: 'quatro_semanas',
    label: 'Um mês seguido',
    metric: BadgeMetric.streakWeeks,
    threshold: 4,
    criterion: 'Guardar em 4 semanas seguidas',
  ),
  dozeSemanas(
    key: 'doze_semanas',
    label: 'Um trimestre',
    metric: BadgeMetric.streakWeeks,
    threshold: 12,
    criterion: 'Guardar em 12 semanas seguidas',
  ),
  primeiraMeta(
    key: 'primeira_meta',
    label: 'Meta cumprida',
    metric: BadgeMetric.completedGoals,
    threshold: 1,
    criterion: 'Atingir o alvo de uma meta',
  );

  const SavingsBadge({
    required this.key,
    required this.label,
    required this.metric,
    required this.threshold,
    required this.criterion,
  });

  /// Chave estável, no formato que `achievements.badge_key` usará na Fase 3.
  ///
  /// Separada do nome da constante Dart de propósito: renomear a constante é
  /// refatoração, e renomear a chave seria perder conquista de quem já a tem.
  final String key;

  /// Nome curto, para o selo.
  final String label;

  final BadgeMetric metric;

  /// Valor da métrica a partir do qual a conquista está desbloqueada.
  final int threshold;

  /// O que é preciso fazer, em uma frase. É o que a conquista bloqueada mostra
  /// no lugar de um cadeado mudo.
  final String criterion;
}

/// Uma conquista cruzada com o quanto falta para ela.
@immutable
class BadgeStatus {
  const BadgeStatus({
    required this.badge,
    required this.current,
    required this.isEarned,
  });

  final SavingsBadge badge;

  /// Valor atual da métrica da conquista.
  final int current;

  final bool isEarned;

  /// Fração do limiar já cumprida, de 0 a 1.
  double get ratio {
    if (isEarned) return 1;
    if (badge.threshold < 1) return 1;
    return (current / badge.threshold).clamp(0.0, 1.0);
  }
}

/// Deriva o estado de todas as conquistas (PRD §8.2).
///
/// Recebe as métricas já apuradas, e não as coleções, porque cada uma delas tem
/// regra própria de janela e de moeda — somar contribuição é `GoalProgress`,
/// contar semana é `SavingsStreak`. Repetir essas regras aqui seria criar uma
/// segunda definição de "quanto foi guardado", que é exatamente como dois
/// números do mesmo app passam a discordar.
///
/// [totalSaved] é nulo quando não há total somável (nenhuma meta, ou moedas
/// misturadas — ver `savingsTotalProvider`). Nesse caso as conquistas de valor
/// ficam em zero em vez de estourar: é honesto, porque sem total apurável não
/// há como afirmar que o limiar foi cruzado.
///
/// A ordem é **desbloqueadas primeiro, depois as mais próximas**.
/// A lista serve a duas perguntas ao mesmo tempo — "o que eu já consegui" e
/// "o que vem agora" —, e a segunda fica invisível se as bloqueadas saírem em
/// ordem de limiar, com a de R\$ 10.000 na frente da que falta R\$ 20.
List<BadgeStatus> deriveBadges({
  required int contributions,
  required Money? totalSaved,
  required int bestStreakWeeks,
  required int completedGoals,
}) {
  int valueOf(BadgeMetric metric) => switch (metric) {
    BadgeMetric.contributions => contributions,
    BadgeMetric.totalSaved => totalSaved?.amountMinor ?? 0,
    BadgeMetric.streakWeeks => bestStreakWeeks,
    BadgeMetric.completedGoals => completedGoals,
  };

  final statuses =
      [
        for (final badge in SavingsBadge.values)
          BadgeStatus(
            badge: badge,
            current: valueOf(badge.metric),
            isEarned: valueOf(badge.metric) >= badge.threshold,
          ),
      ]..sort((a, b) {
        if (a.isEarned != b.isEarned) return a.isEarned ? -1 : 1;
        if (a.isEarned) return a.badge.threshold.compareTo(b.badge.threshold);
        return b.ratio.compareTo(a.ratio);
      });

  return List.unmodifiable(statuses);
}
