import 'package:finance/features/savings/domain/savings_streak.dart';
import 'package:finance/features/savings/presentation/streak_copy.dart';
import 'package:flutter_test/flutter_test.dart';

SavingsStreak streak({
  int weeks = 0,
  int bestWeeks = 0,
  bool isAtRisk = false,
  int daysLeftInWeek = 5,
}) => SavingsStreak(
  weeks: weeks,
  bestWeeks: bestWeeks,
  isAtRisk: isAtRisk,
  daysLeftInWeek: daysLeftInWeek,
);

void main() {
  group('título', () {
    test('sem sequência não anuncia um zero', () {
      final title = StreakCopy.title(streak());

      expect(title, 'Nenhuma sequência agora');
      expect(title, isNot(contains('0')));
    });

    test('uma semana concorda no singular', () {
      expect(
        StreakCopy.title(streak(weeks: 1, bestWeeks: 1)),
        '1 semana seguida',
      );
    });

    test('mais de uma concorda no plural', () {
      expect(
        StreakCopy.title(streak(weeks: 8, bestWeeks: 8)),
        '8 semanas seguidas',
      );
    });
  });

  group('legenda', () {
    test('sem histórico nenhum, convida a começar', () {
      expect(
        StreakCopy.caption(streak()),
        'Guarde algo esta semana para começar uma',
      );
    });

    test('com sequência quebrada, a melhor marca vira crédito, não perda', () {
      final caption = StreakCopy.caption(streak(bestWeeks: 8));

      expect(caption, contains('Sua melhor foi de 8 semanas'));
      expect(caption, contains('começar outra'));
    });

    test(
      'em risco diz quanto tempo ainda há, não quanto falta para falhar',
      () {
        final caption = StreakCopy.caption(
          streak(weeks: 8, bestWeeks: 8, isAtRisk: true, daysLeftInWeek: 3),
        );

        expect(caption, 'Para manter, ainda há 3 dias nesta semana');
      },
    );

    test('no último dia a frase deixa de contar dias', () {
      final caption = StreakCopy.caption(
        streak(weeks: 8, bestWeeks: 8, isAtRisk: true, daysLeftInWeek: 1),
      );

      expect(caption, 'Para manter, ainda hoje nesta semana');
    });

    test('recorde é dito como recorde', () {
      expect(
        StreakCopy.caption(streak(weeks: 5, bestWeeks: 5)),
        'É a sua melhor sequência até agora',
      );
    });

    test('abaixo do recorde, mostra a marca a perseguir', () {
      expect(
        StreakCopy.caption(streak(weeks: 2, bestWeeks: 9)),
        'Sua melhor foi de 9 semanas',
      );
    });

    test('a melhor marca de uma semana concorda no singular', () {
      expect(StreakCopy.caption(streak(bestWeeks: 1)), contains('1 semana —'));
    });
  });

  group('nenhuma frase cobra', () {
    test('nenhum estado usa vocabulário de perda ou punição', () {
      // A RN-3.4 pede tom de incentivo. "Você perdeu sua sequência" é factual e
      // é exatamente o que a regra veta.
      final todos = [
        streak(),
        streak(bestWeeks: 8),
        streak(weeks: 1, bestWeeks: 1),
        streak(weeks: 8, bestWeeks: 8, isAtRisk: true, daysLeftInWeek: 1),
        streak(weeks: 8, bestWeeks: 8, isAtRisk: true, daysLeftInWeek: 6),
        streak(weeks: 2, bestWeeks: 9),
      ];

      for (final s in todos) {
        final frase = '${StreakCopy.title(s)} ${StreakCopy.caption(s)}'
            .toLowerCase();
        for (final palavra in [
          'perde',
          'perdeu',
          'falhou',
          'quebrou',
          'atras',
          'cuidado',
          'erro',
        ]) {
          expect(frase, isNot(contains(palavra)), reason: frase);
        }
      }
    });
  });
}
