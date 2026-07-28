import 'package:core/core.dart';

import '../domain/savings_badge.dart';

/// Texto das conquistas (PRD §8.2), num lugar só.
abstract final class BadgeCopy {
  /// O que ainda falta para desbloquear. Nula quando não há o que dizer.
  ///
  /// Só as métricas em que **um número informa mais que a frase** ganham linha:
  /// "Faltam R\$ 20,00" acrescenta algo a "Acumular R\$ 1.000 guardados", e
  /// "Falta 1 aporte" não acrescenta nada a "Guardar dinheiro pela primeira
  /// vez" — repete a mesma informação com outras palavras, ocupando a linha que
  /// o critério já usa.
  ///
  /// Conquista desbloqueada não tem o que faltar, e devolver "Faltam R\$ 0,00"
  /// seria transformar o troféu em pendência.
  static String? remaining(BadgeStatus status) {
    if (status.isEarned) return null;

    final missing = status.badge.threshold - status.current;
    if (missing < 1) return null;

    return switch (status.badge.metric) {
      BadgeMetric.totalSaved => 'Faltam ${Money.fromMinor(missing).format()}',
      BadgeMetric.streakWeeks =>
        missing == 1 ? 'Falta 1 semana' : 'Faltam $missing semanas',
      // O critério destas já é a frase inteira; um número aqui só repetiria.
      BadgeMetric.contributions || BadgeMetric.completedGoals => null,
    };
  }
}
