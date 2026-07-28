import 'package:core/core.dart';
import 'package:finance/features/savings/domain/goal_progress.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:finance/features/savings/presentation/goal_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

GoalProgress progressOf(
  SavingsGoal goal, {
  List<SavingsContribution> contributions = const [],
  Money monthIncome = const Money.zero(),
}) => GoalProgress.from(
  goal: goal,
  contributions: contributions,
  month: DateTime(2026, 7),
  now: testNow,
  monthIncome: monthIncome,
);

void main() {
  group('alvo', () {
    test('meta por objetivo não leva rótulo de mês', () {
      // Dizer "julho" sugeriria que o acumulado zera no mês seguinte.
      final label = GoalCopy.target(progressOf(testGoal()));

      expect(label, r'de R$ 8.000,00');
      expect(label, isNot(contains('julho')));
    });

    test('meta mensal leva o mês, porque ali o mês distingue algo', () {
      final label = GoalCopy.target(
        progressOf(
          testGoal(type: SavingsGoalType.fixedAmount, targetAmountMinor: 50000),
        ),
      );

      expect(label, r'de R$ 500,00 · julho');
    });

    test('meta percentual sem base diz que não há base', () {
      final label = GoalCopy.target(
        progressOf(testGoal(type: SavingsGoalType.percentageIncome)),
      );

      expect(label, 'sem base neste mês');
    });
  });

  group('status', () {
    test('meta em andamento diz o que falta e até quando', () {
      final status = GoalCopy.status(
        progressOf(
          testGoal(targetDate: DateTime(2027, 3)),
          contributions: [testContribution(minor: 324000)],
        ),
      );

      expect(status, r'Faltam R$ 4.760,00 · até março de 2027');
    });

    test('sem prazo, só o que falta', () {
      final status = GoalCopy.status(
        progressOf(
          testGoal(),
          contributions: [testContribution(minor: 324000)],
        ),
      );

      expect(status, r'Faltam R$ 4.760,00');
    });

    test('meta mensal concluída diz que o mês fechou', () {
      final status = GoalCopy.status(
        progressOf(
          testGoal(type: SavingsGoalType.fixedAmount, targetAmountMinor: 50000),
          contributions: [testContribution(minor: 50000)],
        ),
      );

      expect(status, 'Julho fechado · recomeça no mês que vem');
    });

    test('meta por objetivo concluída diz que foi atingida', () {
      final status = GoalCopy.status(
        progressOf(
          testGoal(targetAmountMinor: 50000),
          contributions: [testContribution(minor: 50000)],
        ),
      );

      expect(status, 'Meta atingida');
    });

    test('meta percentual mostra de onde a base saiu', () {
      final status = GoalCopy.status(
        progressOf(
          testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
          monthIncome: const Money.fromMinor(540000),
        ),
      );

      expect(status, r'20% de R$ 5.400,00 lançados como receita em julho');
    });

    test('meta percentual sem base diz o que falta fazer', () {
      final status = GoalCopy.status(
        progressOf(
          testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
        ),
      );

      expect(status, contains('Nenhuma receita lançada em julho'));
      expect(status, contains('calcular 20%'));
    });

    test('nenhum status usa vocabulário de alarme', () {
      // Meta atrasada é informação, não erro: a frase diz o que falta, e a cor
      // fica fora disso (ver `SavingsProgress`).
      final atrasada = GoalCopy.status(
        progressOf(
          testGoal(
            targetAmountMinor: 100000,
            targetDate: DateTime(2026, 8),
            createdAt: DateTime(2026, 4),
          ),
          contributions: [testContribution(minor: 1000)],
        ),
      );

      for (final palavra in ['atras', 'erro', 'aten', 'cuidado', 'estour']) {
        expect(atrasada.toLowerCase(), isNot(contains(palavra)));
      }
    });
  });

  group('ritmo', () {
    test('sem prazo não há ritmo a explicar', () {
      expect(GoalCopy.pace(progressOf(testGoal())), isNull);
    });

    test('atrasado diz onde estaria', () {
      final pace = GoalCopy.pace(
        progressOf(
          testGoal(
            targetAmountMinor: 100000,
            targetDate: DateTime(2026, 10),
            createdAt: DateTime(2026, 4),
          ),
          contributions: [testContribution(minor: 1000)],
        ),
      );

      expect(pace, contains('No ritmo do prazo você estaria em'));
    });

    test('adiantado é dito como adiantado', () {
      final pace = GoalCopy.pace(
        progressOf(
          testGoal(
            targetAmountMinor: 100000,
            targetDate: DateTime(2026, 10),
            createdAt: DateTime(2026, 4),
          ),
          contributions: [testContribution(minor: 95000)],
        ),
      );

      expect(pace, contains('Adiantado'));
    });
  });

  group('projeção', () {
    test('sem prazo, projeta sem comparar', () {
      final projection = GoalCopy.projection(
        progressOf(
          testGoal(createdAt: DateTime(2026, 4), targetAmountMinor: 100000),
          contributions: [testContribution(minor: 40000)],
        ),
      );

      expect(projection, contains(r'R$ 100,00 por mês'));
      expect(projection, contains('chega aos'));
      expect(projection, isNot(contains('depois do alvo')));
    });

    test('atrasado em relação ao alvo, diz quantos meses', () {
      final projection = GoalCopy.projection(
        progressOf(
          testGoal(
            createdAt: DateTime(2026, 4),
            targetDate: DateTime(2026, 9),
            targetAmountMinor: 100000,
          ),
          contributions: [testContribution(minor: 40000)],
        ),
      );

      // Ritmo de R$ 100/mês fecha em janeiro; o alvo era setembro.
      expect(projection, contains('4 meses depois do alvo'));
    });

    test('um mês de atraso concorda no singular', () {
      final projection = GoalCopy.projection(
        progressOf(
          testGoal(
            createdAt: DateTime(2026, 4),
            targetDate: DateTime(2026, 12),
            targetAmountMinor: 100000,
          ),
          contributions: [testContribution(minor: 40000)],
        ),
      );

      expect(projection, contains('1 mês depois do alvo'));
    });

    test('dentro do prazo é dito como dentro do prazo', () {
      final projection = GoalCopy.projection(
        progressOf(
          testGoal(
            createdAt: DateTime(2026, 4),
            targetDate: DateTime(2027, 6),
            targetAmountMinor: 100000,
          ),
          contributions: [testContribution(minor: 40000)],
        ),
      );

      expect(projection, contains('dentro do prazo'));
    });

    test('sem aporte não há projeção', () {
      expect(GoalCopy.projection(progressOf(testGoal())), isNull);
    });
  });

  group('valor mensal exigido', () {
    test('diz quanto por mês para fechar no prazo', () {
      final required = GoalCopy.requiredMonthly(
        progressOf(
          testGoal(
            createdAt: DateTime(2026, 4),
            targetDate: DateTime(2026, 10),
            targetAmountMinor: 100000,
          ),
          contributions: [testContribution(minor: 40000)],
        ),
      );

      expect(required, r'Para fechar em outubro, seriam R$ 200,00 por mês.');
    });

    test('sem prazo não há valor mensal a exigir', () {
      expect(GoalCopy.requiredMonthly(progressOf(testGoal())), isNull);
    });
  });

  group('aportes a confirmar', () {
    SavingsContribution detected(String id) => testContribution(
      id: id,
      minor: 50000,
      source: ContributionSource.openFinance,
      isConfirmed: false,
    );

    test('sem aporte detectado a frase não existe', () {
      expect(
        GoalCopy.pending(
          progressOf(
            testGoal(),
            contributions: [testContribution(minor: 1000)],
          ),
        ),
        isNull,
      );
    });

    test('um aporte detectado é anunciado no singular', () {
      expect(
        GoalCopy.pending(
          progressOf(testGoal(), contributions: [detected('c1')]),
        ),
        '1 aporte detectado a confirmar',
      );
    });

    test('mais de um concorda no plural', () {
      expect(
        GoalCopy.pending(
          progressOf(
            testGoal(),
            contributions: [detected('c1'), detected('c2')],
          ),
        ),
        '2 aportes detectados a confirmar',
      );
    });

    test('aporte confirmado deixa de ser anunciado', () {
      // O sim do usuário move o valor para o progresso; continuar pedindo
      // confirmação depois disso seria pedir duas vezes a mesma decisão.
      expect(
        GoalCopy.pending(
          progressOf(
            testGoal(),
            contributions: [
              testContribution(
                id: 'c1',
                minor: 50000,
                source: ContributionSource.openFinance,
              ),
            ],
          ),
        ),
        isNull,
      );
    });
  });
}
