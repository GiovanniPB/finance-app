import 'package:design_system/design_system.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:finance/features/savings/presentation/savings_page.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  group('lista de metas', () {
    testWidgets('mostra o total guardado e um card por meta', (tester) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [
            testGoal(),
            testGoal(
              id: 'goal-2',
              name: 'Reserva de emergência',
              targetAmountMinor: 1200000,
            ),
          ],
          contributions: [
            testContribution(id: 'c1', minor: 324000),
            testContribution(id: 'c2', goalId: 'goal-2', minor: 100000),
          ],
        ),
      );

      expect(find.text('Guardado em 2 metas'), findsOneWidget);
      expect(find.text(r'R$ 4.240,00'), findsOneWidget);
      expect(find.byKey(const Key('goal_card_goal-1')), findsOneWidget);
      expect(find.byKey(const Key('goal_card_goal-2')), findsOneWidget);
      expect(find.text('Viagem ao Chile'), findsOneWidget);
    });

    testWidgets('com uma meta só, o rótulo concorda', (tester) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(goals: [testGoal()]),
      );

      expect(find.text('Guardado nesta meta'), findsOneWidget);
      expect(find.text('Guardado em 1 metas'), findsNothing);
    });

    testWidgets('a ação de criar meta fica visível sem rolagem', (
      tester,
    ) async {
      // Com três metas a lista já enche a tela: uma ação no fim da lista seria
      // uma ação que não se vê.
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [
            testGoal(),
            testGoal(id: 'goal-2', name: 'Reserva'),
            testGoal(id: 'goal-3', name: 'Notebook'),
          ],
        ),
      );

      final button = find.byKey(const Key('new_goal'));
      expect(button, findsOneWidget);
      expect(tester.getRect(button).bottom, lessThan(600));
    });

    testWidgets('mostra o mês nas metas mensais e não nas por objetivo', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [
            testGoal(id: 'obj'),
            testGoal(
              id: 'mensal',
              name: 'Guardar todo mês',
              type: SavingsGoalType.fixedAmount,
              targetAmountMinor: 50000,
            ),
          ],
        ),
      );

      expect(find.text(r'de R$ 8.000,00'), findsOneWidget);
      expect(find.textContaining('julho'), findsWidgets);
    });
  });

  group('estado da meta na lista', () {
    testWidgets('meta concluída ganha selo em vez de percentual', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [testGoal(targetAmountMinor: 50000)],
          contributions: [testContribution(minor: 50000)],
        ),
      );

      expect(find.byType(CompletionSeal), findsOneWidget);
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('meta percentual sem receita diz que falta base', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [
            testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
          ],
        ),
      );

      expect(find.textContaining('Nenhuma receita lançada'), findsOneWidget);
      // Um "0%" aqui seria uma afirmação falsa sobre esforço.
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('meta percentual com receita mostra a base derivada', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [
            testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
          ],
        ),
        transactions: [
          testTransaction(
            minor: 540000,
            type: TransactionType.income,
            occurredAt: testNow,
          ),
        ],
      );

      expect(find.textContaining(r'20% de R$ 5.400,00'), findsOneWidget);
      expect(find.text(r'de R$ 1.080,00 · julho'), findsOneWidget);
    });
  });

  group('barra de progresso da meta', () {
    testWidgets('nunca usa a cor de orçamento estourado', (tester) async {
      // Guarda contra o erro que a fatia de contas cometeu com a fatura de
      // cartão: `moneyOver` é reservado a orçamento estourado, e meta atrasada
      // não é erro.
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [
            testGoal(
              targetAmountMinor: 100000,
              targetDate: DateTime(2026, 8),
              createdAt: DateTime(2026, 4),
            ),
          ],
          contributions: [testContribution(minor: 1000)],
        ),
      );

      final context = tester.element(find.byType(SavingsProgress).first);
      final tokens = Theme.of(context).extension<AppTokens>()!;
      final indicator = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byType(SavingsProgress).first,
          matching: find.byType(LinearProgressIndicator),
        ),
      );

      expect(indicator.valueColor?.value, isNot(tokens.moneyOver));
      expect(indicator.valueColor?.value, isNot(tokens.attention));
      expect(
        indicator.valueColor?.value,
        Theme.of(context).colorScheme.primary,
      );
    });

    testWidgets('só a meta com prazo desenha marca de ritmo', (tester) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [
            testGoal(id: 'com-prazo', targetDate: DateTime(2027, 3)),
            testGoal(id: 'sem-prazo', name: 'Reserva'),
          ],
        ),
      );

      final withDeadline = tester.widget<SavingsProgress>(
        find.descendant(
          of: find.byKey(const Key('goal_card_com-prazo')),
          matching: find.byType(SavingsProgress),
        ),
      );
      final without = tester.widget<SavingsProgress>(
        find.descendant(
          of: find.byKey(const Key('goal_card_sem-prazo')),
          matching: find.byType(SavingsProgress),
        ),
      );

      expect(withDeadline.paceRatio, isNotNull);
      expect(without.paceRatio, isNull);
    });
  });

  group('estado vazio', () {
    testWidgets('sem meta alguma, ocupa a tela e oferece a saída', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(),
      );

      expect(find.text('Nenhuma meta ainda'), findsOneWidget);
      expect(find.text('Criar primeira meta'), findsOneWidget);
      // Sem o momento alto zerado: "R$ 0,00" em 40px anunciaria fracasso antes
      // de haver o que medir.
      expect(find.byType(BalanceHeader), findsNothing);
    });
  });
}
