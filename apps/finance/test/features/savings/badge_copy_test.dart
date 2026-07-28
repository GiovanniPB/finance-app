import 'package:finance/features/savings/domain/savings_badge.dart';
import 'package:finance/features/savings/presentation/badge_copy.dart';
import 'package:flutter_test/flutter_test.dart';

BadgeStatus status(SavingsBadge badge, {required int current}) => BadgeStatus(
  badge: badge,
  current: current,
  isEarned: current >= badge.threshold,
);

void main() {
  group('o que falta', () {
    test('valor faltante vira dinheiro formatado', () {
      expect(
        BadgeCopy.remaining(status(SavingsBadge.milGuardados, current: 98000)),
        r'Faltam R$ 20,00',
      );
    });

    test('semanas faltantes concordam no plural', () {
      expect(
        BadgeCopy.remaining(status(SavingsBadge.dozeSemanas, current: 9)),
        'Faltam 3 semanas',
      );
    });

    test('uma semana concorda no singular', () {
      expect(
        BadgeCopy.remaining(status(SavingsBadge.dozeSemanas, current: 11)),
        'Falta 1 semana',
      );
    });

    test('conquista desbloqueada não tem o que faltar', () {
      // "Faltam R$ 0,00" transformaria o troféu em pendência.
      expect(
        BadgeCopy.remaining(status(SavingsBadge.cemGuardados, current: 10000)),
        isNull,
      );
    });

    test('métrica cujo critério já é a frase inteira não repete', () {
      for (final badge in [
        SavingsBadge.primeiroAporte,
        SavingsBadge.primeiraMeta,
      ]) {
        expect(
          BadgeCopy.remaining(status(badge, current: 0)),
          isNull,
          reason: badge.key,
        );
      }
    });
  });
}
