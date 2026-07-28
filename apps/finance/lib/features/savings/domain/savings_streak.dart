import 'package:flutter/foundation.dart';

import 'savings_contribution.dart';

/// A sequência de semanas em que houve aporte confirmado (RN-3.4).
///
/// **Derivado, nunca coluna** — [ADR 0007](../../../../../docs/adr/0007-agregado-derivado-vs-coluna.md).
/// Duas réplicas offline com as mesmas contribuições chegam ao mesmo streak,
/// que é exatamente o teste que a ADR propõe. Não há migration nesta fatia.
///
/// ─────────────────────────────────────────────────────────────────────────
/// A UNIDADE É A SEMANA, E A SEMANA CORRENTE NÃO QUEBRA NADA
///
/// A RN-3.4 fala em "poupou toda semana por 8 semanas". A escolha que importa
/// não é o tamanho da janela, é **onde a contagem começa**: a semana corrente
/// ainda não terminou, então não ter aporte nela é "ainda dá tempo", não
/// "quebrou".
///
/// Contar a partir da semana corrente e exigir aporte nela zeraria a sequência
/// de qualquer pessoa na segunda-feira de manhã — o app anunciaria fracasso por
/// causa do calendário, não do comportamento. Por isso a contagem começa na
/// semana corrente **se** houver aporte nela, e na anterior caso contrário; só
/// uma semana **encerrada** sem aporte interrompe a sequência.
///
/// É a mesma razão pela qual [isAtRisk] existe em vez de o streak simplesmente
/// cair: o estado "você tem 8 semanas e esta ainda está em aberto" é diferente
/// de "você tem 8 semanas e está tudo certo", e a tela precisa poder dizer o
/// primeiro sem soar como cobrança (ver a doc de `AppTokens`: aqui não há
/// vermelho nem âmbar).
@immutable
class SavingsStreak {
  const SavingsStreak({
    required this.weeks,
    required this.bestWeeks,
    required this.isAtRisk,
    required this.daysLeftInWeek,
  });

  /// Deriva a sequência das contribuições **confirmadas** do espaço.
  ///
  /// Contribuição pendente (detectada pelo Open Finance e ainda sem o sim) não
  /// alimenta streak, pelo mesmo motivo de não entrar no progresso: até o sim,
  /// ela é uma proposta, e uma proposta não é um hábito.
  factory SavingsStreak.from({
    required List<SavingsContribution> contributions,
    required DateTime now,
  }) {
    final weeksWithContribution = <int>{};
    for (final contribution in contributions) {
      if (contribution.isPending) continue;
      // `contributed_at` é `timestamptz`: comparar em local é o que faz "esta
      // semana" significar a semana do fuso do usuário, e não a de UTC — mesma
      // escolha de `GoalProgress._isSameMonth`.
      weeksWithContribution.add(
        _weekOrdinal(contribution.contributedAt.toLocal()),
      );
    }

    final currentWeek = _weekOrdinal(now);
    final hasThisWeek = weeksWithContribution.contains(currentWeek);

    // O ponto de partida é a semana corrente só quando ela já tem aporte; caso
    // contrário é a anterior, que é o que impede a segunda-feira de zerar tudo.
    var cursor = hasThisWeek ? currentWeek : currentWeek - 1;
    var streak = 0;
    while (weeksWithContribution.contains(cursor)) {
      streak++;
      cursor--;
    }

    return SavingsStreak(
      weeks: streak,
      bestWeeks: _longestRun(weeksWithContribution),
      // Só está em risco quem tem o que perder: sem sequência não há risco, há
      // ausência — e são frases diferentes na tela.
      isAtRisk: streak > 0 && !hasThisWeek,
      daysLeftInWeek: DateTime.daysPerWeek - now.weekday + 1,
    );
  }

  /// Semanas consecutivas até agora. Zero quando a última semana encerrada não
  /// teve aporte.
  final int weeks;

  /// A maior sequência já alcançada, em qualquer momento do histórico.
  ///
  /// Existe para o streak atual não ser a única leitura possível: quem quebrou
  /// uma sequência de 12 semanas e está na segunda ainda tem 12 no currículo, e
  /// mostrar só o número corrente apagaria isso.
  final int bestWeeks;

  /// Há sequência viva e a semana corrente ainda não teve aporte.
  ///
  /// **Não é alerta.** É o gancho para uma frase de incentivo ("ainda há 3 dias
  /// nesta semana"), que é o que a RN-3.4 pede ao dizer que a quebra é
  /// comunicada com tom de incentivo, não de punição.
  final bool isAtRisk;

  /// Dias restantes na semana corrente, incluindo hoje. Sempre de 1 a 7.
  final int daysLeftInWeek;

  /// Há uma sequência para mostrar.
  bool get isActive => weeks > 0;

  /// A sequência corrente é a melhor de todas — o momento de recorde.
  ///
  /// Empate conta como recorde: quem igualou a melhor marca está vivendo o
  /// recorde, não perseguindo-o.
  bool get isPersonalBest => isActive && weeks >= bestWeeks;

  /// A semana como número contínuo, para comparar semana a semana em vez de
  /// instante a instante — mesma ideia de `_monthsBetween` em `GoalProgress`.
  ///
  /// A semana começa na **segunda**, que é o que `DateTime.weekday` já usa
  /// (1 = segunda). Recuar até a segunda e dividir por sete dá um ordinal
  /// estável que atravessa virada de mês e de ano sem caso especial.
  static int _weekOrdinal(DateTime date) {
    final monday = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    // Divisão por dias inteiros a partir de uma data fixa. `toUtc` não entra
    // aqui de propósito: `monday` já é meia-noite local, e converter reintroduz
    // o fuso que a normalização acabou de tirar.
    return monday.difference(DateTime(2000)).inDays ~/ DateTime.daysPerWeek;
  }

  /// A maior corrida de semanas consecutivas no conjunto.
  static int _longestRun(Set<int> weeks) {
    var best = 0;
    for (final week in weeks) {
      // Só conta a partir do início de uma corrida: se a semana anterior também
      // tem aporte, esta já foi contada por ela. É o que mantém a varredura
      // linear em vez de quadrática.
      if (weeks.contains(week - 1)) continue;

      var run = 0;
      var cursor = week;
      while (weeks.contains(cursor)) {
        run++;
        cursor++;
      }
      if (run > best) best = run;
    }
    return best;
  }
}
