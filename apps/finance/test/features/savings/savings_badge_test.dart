import 'package:core/core.dart';
import 'package:finance/features/savings/domain/savings_badge.dart';
import 'package:flutter_test/flutter_test.dart';

List<BadgeStatus> badgesOf({
  int contributions = 0,
  int? totalMinor,
  int bestStreakWeeks = 0,
  int completedGoals = 0,
}) => deriveBadges(
  contributions: contributions,
  totalSaved: totalMinor == null ? null : Money.fromMinor(totalMinor),
  bestStreakWeeks: bestStreakWeeks,
  completedGoals: completedGoals,
);

BadgeStatus statusOf(List<BadgeStatus> all, SavingsBadge badge) =>
    all.firstWhere((s) => s.badge == badge);

void main() {
  group('desbloqueio', () {
    test('sem histórico nenhuma conquista está desbloqueada', () {
      expect(badgesOf().where((s) => s.isEarned), isEmpty);
    });

    test('o primeiro aporte desbloqueia o primeiro passo', () {
      final badges = badgesOf(contributions: 1, totalMinor: 500);

      expect(statusOf(badges, SavingsBadge.primeiroAporte).isEarned, isTrue);
      expect(statusOf(badges, SavingsBadge.cemGuardados).isEarned, isFalse);
    });

    test('o limiar exato desbloqueia — não é "mais que"', () {
      expect(
        statusOf(
          badgesOf(contributions: 1, totalMinor: 10000),
          SavingsBadge.cemGuardados,
        ).isEarned,
        isTrue,
      );
    });

    test('um centavo a menos não desbloqueia', () {
      expect(
        statusOf(
          badgesOf(contributions: 1, totalMinor: 9999),
          SavingsBadge.cemGuardados,
        ).isEarned,
        isFalse,
      );
    });

    test('cruzar um limiar alto leva os baixos junto', () {
      final badges = badgesOf(contributions: 3, totalMinor: 1000000);

      for (final badge in [
        SavingsBadge.cemGuardados,
        SavingsBadge.milGuardados,
        SavingsBadge.dezMilGuardados,
      ]) {
        expect(statusOf(badges, badge).isEarned, isTrue, reason: badge.key);
      }
    });

    test('a sequência desbloqueia pela melhor marca, não pela corrente', () {
      // Quem fez 12 semanas e quebrou não perde a conquista: `bestStreakWeeks`
      // é o insumo justamente por isso.
      final badges = badgesOf(bestStreakWeeks: 12);

      expect(statusOf(badges, SavingsBadge.quatroSemanas).isEarned, isTrue);
      expect(statusOf(badges, SavingsBadge.dozeSemanas).isEarned, isTrue);
    });

    test('meta atingida desbloqueia a conquista de meta', () {
      expect(
        statusOf(
          badgesOf(completedGoals: 1),
          SavingsBadge.primeiraMeta,
        ).isEarned,
        isTrue,
      );
    });
  });

  group('total não apurável', () {
    test('sem total somável as conquistas de valor ficam bloqueadas', () {
      // Acontece com moedas misturadas: sem total apurável não há como afirmar
      // que o limiar foi cruzado, e afirmar seria pior do que não afirmar.
      final badges = badgesOf(contributions: 40, bestStreakWeeks: 4);

      expect(statusOf(badges, SavingsBadge.cemGuardados).isEarned, isFalse);
      expect(statusOf(badges, SavingsBadge.cemGuardados).current, 0);
      // O que não depende de valor continua valendo.
      expect(statusOf(badges, SavingsBadge.primeiroAporte).isEarned, isTrue);
      expect(statusOf(badges, SavingsBadge.quatroSemanas).isEarned, isTrue);
    });
  });

  group('progresso do que falta', () {
    test('conquista desbloqueada está cheia', () {
      expect(
        statusOf(
          badgesOf(contributions: 1, totalMinor: 20000),
          SavingsBadge.cemGuardados,
        ).ratio,
        1,
      );
    });

    test('metade do caminho é metade da barra', () {
      expect(
        statusOf(badgesOf(totalMinor: 50000), SavingsBadge.milGuardados).ratio,
        0.5,
      );
    });

    test('a razão nunca passa de 1 nem fica negativa', () {
      final badges = badgesOf(contributions: 99, totalMinor: 0);

      for (final status in badges) {
        expect(status.ratio, inInclusiveRange(0, 1), reason: status.badge.key);
      }
    });
  });

  group('ordem da lista', () {
    test('desbloqueadas vêm primeiro, sem intercalar', () {
      final badges = badgesOf(contributions: 1, totalMinor: 10000);
      final firstLocked = badges.indexWhere((s) => !s.isEarned);

      expect(badges.take(firstLocked).every((s) => s.isEarned), isTrue);
      expect(badges.skip(firstLocked).every((s) => !s.isEarned), isTrue);
    });

    test('entre as bloqueadas, a mais próxima vem antes', () {
      // O que isto guarda: em ordem de limiar, a de R$ 10.000 apareceria na
      // frente da que falta R$ 20 — e "o que vem agora" ficaria invisível.
      final locked = badgesOf(
        contributions: 1,
        totalMinor: 98000,
      ).where((s) => !s.isEarned).toList();

      expect(locked.first.badge, SavingsBadge.milGuardados);
      for (var i = 1; i < locked.length; i++) {
        expect(locked[i - 1].ratio, greaterThanOrEqualTo(locked[i].ratio));
      }
    });

    test('toda conquista aparece exatamente uma vez', () {
      final badges = badgesOf(contributions: 2, totalMinor: 30000);

      expect(badges.length, SavingsBadge.values.length);
      expect(
        badges.map((s) => s.badge).toSet().length,
        SavingsBadge.values.length,
      );
    });

    test('a lista devolvida não é modificável', () {
      expect(() => badgesOf().clear(), throwsUnsupportedError);
    });
  });

  group('chaves', () {
    test('são estáveis e únicas — renomear perderia conquista', () {
      final keys = SavingsBadge.values.map((b) => b.key).toList();

      expect(keys.toSet().length, keys.length);
      expect(keys, everyElement(matches(RegExp(r'^[a-z][a-z0-9_]*$'))));
    });
  });
}
