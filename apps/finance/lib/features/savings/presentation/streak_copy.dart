import '../domain/savings_streak.dart';

/// Texto da sequência de semanas (RN-3.4), num lugar só.
///
/// ─────────────────────────────────────────────────────────────────────────
/// A REGRA QUE MANDA AQUI: NENHUMA FRASE COBRA
///
/// A RN-3.4 diz que a quebra de streak é comunicada "com tom de incentivo, não
/// de punição". Na prática isso proíbe três coisas que seriam o caminho fácil:
///
///  • **nada de perda.** "Você perdeu sua sequência de 8 semanas" é factual e é
///    exatamente o que a regra veta. O que sobrou de 8 semanas é uma marca
///    pessoal, e a frase fala dela como algo que se tem, não que se perdeu;
///  • **nada de contagem regressiva ameaçadora.** Em risco, a frase diz
///    quantos dias **ainda há**, não quanto tempo falta para falhar;
///  • **nada de zero em destaque.** Sem sequência, a tela convida a começar
///    outra; não anuncia um `0`.
///
/// É o mesmo princípio da doc de `AppTokens` (despesa não é vermelha) e do
/// `GoalCopy.status` (meta atrasada não é alarme), aplicado a hábito.
abstract final class StreakCopy {
  /// A linha principal. Nunca é um número sozinho.
  static String title(SavingsStreak streak) {
    if (!streak.isActive) return 'Nenhuma sequência agora';
    return streak.weeks == 1
        ? '1 semana seguida'
        : '${streak.weeks} semanas seguidas';
  }

  /// A linha de apoio, que é onde o incentivo mora.
  static String caption(SavingsStreak streak) {
    if (!streak.isActive) {
      return streak.bestWeeks > 0
          ? 'Sua melhor foi de ${_weeks(streak.bestWeeks)} — guarde algo esta '
                'semana para começar outra'
          : 'Guarde algo esta semana para começar uma';
    }

    if (streak.isAtRisk) {
      final days = streak.daysLeftInWeek;
      final prazo = days == 1 ? 'ainda hoje' : 'ainda há $days dias';
      return 'Para manter, $prazo nesta semana';
    }

    if (streak.isPersonalBest) return 'É a sua melhor sequência até agora';
    return 'Sua melhor foi de ${_weeks(streak.bestWeeks)}';
  }

  static String _weeks(int count) => count == 1 ? '1 semana' : '$count semanas';
}
