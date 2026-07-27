import 'package:core/core.dart';
import 'package:finance/features/savings/domain/goal_progress.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Compõe o progresso com o mês em foco e o "agora" fixos do harness.
GoalProgress progressOf(
  SavingsGoal goal, {
  List<SavingsContribution> contributions = const [],
  DateTime? month,
  DateTime? now,
  Money monthIncome = const Money.zero(),
}) => GoalProgress.from(
  goal: goal,
  contributions: contributions,
  month: month ?? DateTime(2026, 7),
  now: now ?? testNow,
  monthIncome: monthIncome,
);

void main() {
  group('o que conta como progresso', () {
    test('só contribuição confirmada entra no acumulado (RN-3.3)', () {
      final progress = progressOf(
        testGoal(),
        contributions: [
          testContribution(id: 'c1', minor: 40000),
          testContribution(
            id: 'c2',
            minor: 30000,
            source: ContributionSource.openFinance,
            isConfirmed: false,
          ),
        ],
      );

      expect(progress.contributed, const Money.fromMinor(40000));
      expect(progress.pendingCount, 1);
    });

    test('contribuição de outra meta é descartada', () {
      // A filtragem é do domínio, e não do chamador: nenhuma tela deve
      // conseguir contar o que não é dela.
      final progress = progressOf(
        testGoal(),
        contributions: [
          testContribution(id: 'c1', minor: 40000),
          testContribution(id: 'c2', goalId: 'goal-2', minor: 99900),
        ],
      );

      expect(progress.contributed, const Money.fromMinor(40000));
    });

    test('aporte em outra moeda é ignorado em vez de derrubar a lista', () {
      final progress = progressOf(
        testGoal(),
        contributions: [
          testContribution(id: 'c1', minor: 40000),
          testContribution(id: 'c2', minor: 10000).copyWith(
            amount: const Money.fromMinor(10000, currency: 'USD'),
          ),
        ],
      );

      expect(progress.contributed, const Money.fromMinor(40000));
    });
  });

  group('a janela depende do tipo', () {
    test('meta por objetivo acumula a vida toda', () {
      final progress = progressOf(
        testGoal(),
        contributions: [
          testContribution(id: 'c1', minor: 40000, contributedAt: testNow),
          testContribution(
            id: 'c2',
            minor: 30000,
            contributedAt: DateTime(2026, 5, 10),
          ),
        ],
      );

      expect(progress.contributed, const Money.fromMinor(70000));
      expect(progress.lifetimeContributed, const Money.fromMinor(70000));
    });

    test('meta mensal só conta o mês em foco', () {
      final progress = progressOf(
        testGoal(type: SavingsGoalType.fixedAmount, targetAmountMinor: 50000),
        contributions: [
          testContribution(id: 'c1', minor: 40000, contributedAt: testNow),
          testContribution(
            id: 'c2',
            minor: 30000,
            contributedAt: DateTime(2026, 5, 10),
          ),
        ],
      );

      expect(progress.contributed, const Money.fromMinor(40000));
      // O total de sempre continua disponível — é o que alimenta o ritmo.
      expect(progress.lifetimeContributed, const Money.fromMinor(70000));
    });

    test('meta mensal não fica concluída para sempre no mês seguinte', () {
      final goal = testGoal(
        type: SavingsGoalType.fixedAmount,
        targetAmountMinor: 50000,
      );
      final contributions = [
        testContribution(id: 'c1', minor: 50000, contributedAt: testNow),
      ];

      final july = progressOf(goal, contributions: contributions);
      final august = progressOf(
        goal,
        contributions: contributions,
        month: DateTime(2026, 8),
      );

      expect(july.isComplete, isTrue);
      expect(august.isComplete, isFalse);
      expect(august.contributed.isZero, isTrue);
    });
  });

  group('o alvo depende do tipo', () {
    test('objetivo e valor fixo usam o valor da meta', () {
      expect(
        progressOf(testGoal()).target,
        const Money.fromMinor(800000),
      );
      expect(
        progressOf(
          testGoal(type: SavingsGoalType.fixedAmount, targetAmountMinor: 50000),
        ).target,
        const Money.fromMinor(50000),
      );
    });

    test('percentual aplica a fatia sobre a renda do mês', () {
      final progress = progressOf(
        testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
        monthIncome: const Money.fromMinor(540000),
      );

      expect(progress.target, const Money.fromMinor(108000));
      expect(progress.needsIncome, isFalse);
    });

    test('percentual trunca em vez de arredondar para cima', () {
      final progress = progressOf(
        testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
        monthIncome: const Money.fromMinor(540001),
      );

      // 20% de 540001 é 108000,2 — pedir 108001 seria cobrar um centavo que a
      // conta não dá.
      expect(progress.target, const Money.fromMinor(108000));
    });

    test('percentual sem receita no mês é "sem base", não 0%', () {
      final progress = progressOf(
        testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
      );

      expect(progress.needsIncome, isTrue);
      expect(progress.hasTarget, isFalse);
      expect(progress.ratio, 0);
      // Sem alvo, "concluída" seria uma afirmação falsa.
      expect(progress.isComplete, isFalse);
    });
  });

  group('razão, conclusão e restante', () {
    test('razão e percentual', () {
      final progress = progressOf(
        testGoal(),
        contributions: [testContribution(minor: 324000)],
      );

      expect(progress.ratio, closeTo(0.405, 0.001));
      expect(progress.percent, 41);
      expect(progress.remaining, const Money.fromMinor(476000));
      expect(progress.isComplete, isFalse);
    });

    test('guardar além do alvo conclui e o restante não fica negativo', () {
      final progress = progressOf(
        testGoal(targetAmountMinor: 100000),
        contributions: [testContribution(minor: 120000)],
      );

      expect(progress.isComplete, isTrue);
      expect(progress.ratio, greaterThan(1));
      expect(progress.remaining.isZero, isTrue);
    });
  });

  group('marca de ritmo', () {
    test('meta sem prazo não tem ritmo', () {
      expect(progressOf(testGoal()).paceRatio, isNull);
      expect(progressOf(testGoal()).isBehind, isFalse);
    });

    test('ritmo é a fração do prazo já decorrida', () {
      // Criada em 1º de abril, prazo em 1º de outubro: em 27 de julho passaram
      // pouco menos de dois terços do caminho.
      final progress = progressOf(
        testGoal(
          createdAt: DateTime(2026, 4),
          targetDate: DateTime(2026, 10),
        ),
      );

      expect(progress.paceRatio, closeTo(0.64, 0.02));
    });

    test('prazo vencido satura em 1, sem passar disso', () {
      final progress = progressOf(
        testGoal(
          createdAt: DateTime(2026, 4),
          targetDate: DateTime(2026, 6),
        ),
      );

      expect(progress.paceRatio, 1.0);
    });

    test('atrasado quando guardou menos que o tempo consumido', () {
      final goal = testGoal(
        createdAt: DateTime(2026, 4),
        targetDate: DateTime(2026, 10),
        targetAmountMinor: 100000,
      );

      final behind = progressOf(
        goal,
        contributions: [testContribution(minor: 10000)],
      );
      final ahead = progressOf(
        goal,
        contributions: [testContribution(minor: 90000)],
      );

      expect(behind.isBehind, isTrue);
      expect(ahead.isBehind, isFalse);
    });

    test('meta concluída nunca conta como atrasada', () {
      final progress = progressOf(
        testGoal(
          createdAt: DateTime(2026, 4),
          targetDate: DateTime(2026, 6),
          targetAmountMinor: 100000,
        ),
        contributions: [testContribution(minor: 100000)],
      );

      expect(progress.isBehind, isFalse);
    });
  });

  group('ritmo mensal e projeção', () {
    test('o ritmo divide pelos meses decorridos, não pelos com aporte', () {
      // Criada em abril; em julho são quatro meses decorridos. R$ 400 no total
      // dá R$ 100 por mês, não R$ 400.
      final progress = progressOf(
        testGoal(createdAt: DateTime(2026, 4)),
        contributions: [testContribution(minor: 40000)],
      );

      expect(progress.monthlyPace, const Money.fromMinor(10000));
    });

    test('projeta a data em que o alvo fecha no ritmo atual', () {
      final progress = progressOf(
        testGoal(createdAt: DateTime(2026, 4), targetAmountMinor: 100000),
        contributions: [testContribution(minor: 40000)],
      );

      // Ritmo de R$ 100/mês e R$ 600 faltando: seis meses a partir de julho.
      expect(progress.monthlyPace, const Money.fromMinor(10000));
      expect(progress.projectedCompletion, DateTime(2027));
    });

    test('sem nenhum aporte não há projeção — seria uma data infinita', () {
      final progress = progressOf(testGoal());

      expect(progress.monthlyPace.isZero, isTrue);
      expect(progress.projectedCompletion, isNull);
    });

    test('meta concluída não projeta nada', () {
      final progress = progressOf(
        testGoal(targetAmountMinor: 30000),
        contributions: [testContribution(minor: 40000)],
      );

      expect(progress.projectedCompletion, isNull);
      expect(progress.requiredMonthly, isNull);
    });

    test('quanto guardar por mês para fechar no prazo', () {
      final progress = progressOf(
        testGoal(
          createdAt: DateTime(2026, 4),
          targetDate: DateTime(2026, 10),
          targetAmountMinor: 100000,
        ),
        contributions: [testContribution(minor: 40000)],
      );

      // Faltam R$ 600 e três meses (julho → outubro).
      expect(progress.requiredMonthly, const Money.fromMinor(20000));
    });

    test('prazo neste mês ou vencido divide por um, não por zero', () {
      final progress = progressOf(
        testGoal(
          createdAt: DateTime(2026, 4),
          targetDate: DateTime(2026, 7, 30),
          targetAmountMinor: 100000,
        ),
        contributions: [testContribution(minor: 40000)],
      );

      expect(progress.requiredMonthly, const Money.fromMinor(60000));
    });

    test('sem prazo não há valor mensal exigido', () {
      expect(progressOf(testGoal()).requiredMonthly, isNull);
    });
  });
}
