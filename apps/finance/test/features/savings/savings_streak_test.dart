import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:finance/features/savings/domain/savings_streak.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Quarta-feira, 2026-07-15. Meio de semana de propósito: numa segunda ou num
/// domingo os casos de fronteira se escondem atrás do próprio calendário.
final _now = DateTime(2026, 7, 15, 10);

/// Uma data, escrita por extenso. Existe porque `_day(2026, 7, 1)` dispara
/// `avoid_redundant_argument_values` (dia 1 é o padrão) — e escrever
/// `DateTime(2026, 7)` no meio de uma lista de datas esconde justamente o dia,
/// que é o que cada caso destes está escolhendo.
DateTime _day(int year, int month, int day) => DateTime(year, month, day);

SavingsStreak streakOf(List<DateTime> dates, {DateTime? now}) =>
    SavingsStreak.from(
      contributions: [
        for (final (index, date) in dates.indexed)
          testContribution(id: 'c$index', minor: 10000, contributedAt: date),
      ],
      now: now ?? _now,
    );

void main() {
  group('sequência corrente', () {
    test('sem aporte nenhum não há sequência', () {
      final streak = streakOf(const []);

      expect(streak.weeks, 0);
      expect(streak.isActive, isFalse);
      // Sem sequência não há risco — há ausência, e são frases diferentes.
      expect(streak.isAtRisk, isFalse);
    });

    test('aporte só nesta semana já é uma semana', () {
      expect(streakOf([_day(2026, 7, 14)]).weeks, 1);
    });

    test('semanas consecutivas somam', () {
      final streak = streakOf([
        _day(2026, 7, 14), // esta semana
        _day(2026, 7, 8), // anterior
        _day(2026, 7, 1), // retrasada
      ]);

      expect(streak.weeks, 3);
      expect(streak.isAtRisk, isFalse);
    });

    test('dois aportes na mesma semana contam como uma', () {
      // O streak mede o hábito, não o volume: guardar duas vezes na quarta não
      // é mais regular do que guardar uma.
      expect(streakOf([_day(2026, 7, 13), _day(2026, 7, 14)]).weeks, 1);
    });

    test('semana encerrada sem aporte interrompe', () {
      final streak = streakOf([
        _day(2026, 7, 14), // esta semana
        // a semana de 6 a 12 de julho ficou vazia
        _day(2026, 7, 1),
      ]);

      expect(streak.weeks, 1);
    });
  });

  group('a semana corrente não quebra a sequência', () {
    test('sem aporte nesta semana, a sequência anterior continua de pé', () {
      // O bug que isto guarda: contar a partir da semana corrente e exigir
      // aporte nela zeraria o streak de todo mundo toda segunda de manhã.
      final streak = streakOf([
        _day(2026, 7, 8), // semana passada
        _day(2026, 7, 1),
        _day(2026, 6, 24),
      ]);

      expect(streak.weeks, 3);
      expect(streak.isAtRisk, isTrue);
    });

    test('em risco deixa de ser risco assim que o aporte entra', () {
      final streak = streakOf([
        _day(2026, 7, 14), // esta semana
        _day(2026, 7, 8),
        _day(2026, 7, 1),
      ]);

      expect(streak.weeks, 3);
      expect(streak.isAtRisk, isFalse);
    });

    test(
      'na segunda-feira de manhã a sequência da semana anterior sobrevive',
      () {
        // 2026-07-13 é segunda. Zero aporte na semana nova, e o streak segue.
        final streak = streakOf([
          _day(2026, 7, 8),
          _day(2026, 7, 1),
        ], now: DateTime(2026, 7, 13, 8));

        expect(streak.weeks, 2);
        expect(streak.isAtRisk, isTrue);
        expect(streak.daysLeftInWeek, 7);
      },
    );

    test('duas semanas encerradas sem aporte zeram mesmo', () {
      final streak = streakOf([
        _day(2026, 6, 24),
      ], now: _day(2026, 7, 15));

      expect(streak.weeks, 0);
      expect(streak.isAtRisk, isFalse);
    });
  });

  group('melhor sequência', () {
    test('guarda a maior corrida mesmo depois de quebrada', () {
      final streak = streakOf([
        // corrida de 3, encerrada
        _day(2026, 5, 6),
        _day(2026, 5, 13),
        _day(2026, 5, 20),
        // pulou junho inteiro; corrida nova de 1
        _day(2026, 7, 14),
      ]);

      expect(streak.weeks, 1);
      expect(streak.bestWeeks, 3);
      expect(streak.isPersonalBest, isFalse);
    });

    test('a corrida corrente sendo a maior é recorde', () {
      final streak = streakOf([
        _day(2026, 7, 14),
        _day(2026, 7, 8),
      ]);

      expect(streak.weeks, 2);
      expect(streak.bestWeeks, 2);
      expect(streak.isPersonalBest, isTrue);
    });

    test('igualar a melhor marca já é viver o recorde', () {
      final streak = streakOf([
        _day(2026, 5, 6),
        _day(2026, 5, 13),
        _day(2026, 7, 8),
        _day(2026, 7, 14),
      ]);

      expect(streak.weeks, 2);
      expect(streak.bestWeeks, 2);
      expect(streak.isPersonalBest, isTrue);
    });
  });

  group('contribuição pendente', () {
    test('não alimenta streak — proposta não é hábito', () {
      final streak = SavingsStreak.from(
        contributions: [
          testContribution(
            id: 'c1',
            minor: 10000,
            contributedAt: _day(2026, 7, 14),
            source: ContributionSource.openFinance,
            isConfirmed: false,
          ),
        ],
        now: _now,
      );

      expect(streak.weeks, 0);
    });

    test('a mesma linha confirmada passa a contar', () {
      final streak = SavingsStreak.from(
        contributions: [
          testContribution(
            id: 'c1',
            minor: 10000,
            contributedAt: _day(2026, 7, 14),
            source: ContributionSource.openFinance,
          ),
        ],
        now: _now,
      );

      expect(streak.weeks, 1);
    });
  });

  group('dias restantes na semana', () {
    test('na quarta faltam cinco dias, contando hoje', () {
      expect(streakOf(const []).daysLeftInWeek, 5);
    });

    test('no domingo falta um — o próprio domingo', () {
      expect(
        streakOf(const [], now: _day(2026, 7, 19)).daysLeftInWeek,
        1,
      );
    });
  });

  group('viradas de calendário', () {
    test('a sequência atravessa a virada de mês', () {
      final streak = streakOf([
        _day(2026, 7, 14),
        _day(2026, 7, 8),
        _day(2026, 7, 1),
        _day(2026, 6, 24),
      ]);

      expect(streak.weeks, 4);
    });

    test('a sequência atravessa a virada de ano', () {
      final streak = streakOf([
        _day(2026, 1, 5),
        _day(2025, 12, 29),
        _day(2025, 12, 22),
      ], now: _day(2026, 1, 7));

      expect(streak.weeks, 3);
    });
  });
}
