import 'package:design_system/design_system.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
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

  group('aporte detectado pelo Open Finance', () {
    testWidgets('o card anuncia que há algo a confirmar', (tester) async {
      // Sem esta linha, o aporte que a ingestão detectou só existiria para quem
      // abrisse a meta certa por conta própria — a confirmação mora no detalhe.
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [
            testContribution(
              id: 'c1',
              minor: 50000,
              source: ContributionSource.openFinance,
              isConfirmed: false,
            ),
          ],
        ),
      );

      expect(find.byKey(const Key('goal_card_pending')), findsOneWidget);
      expect(find.text('1 aporte detectado a confirmar'), findsOneWidget);
    });

    testWidgets('o valor detectado não entra no total guardado', (
      tester,
    ) async {
      // RN-3.3: só o sim do usuário move o número grande. Um pendente somado
      // aqui faria a meta andar sozinha.
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [
            testContribution(id: 'c1', minor: 100000),
            testContribution(
              id: 'c2',
              minor: 50000,
              source: ContributionSource.openFinance,
              isConfirmed: false,
            ),
          ],
        ),
      );

      // Duas vezes: o total no topo e o acumulado do card. O que importa é que
      // nenhum dos dois virou R$ 1.500,00.
      expect(find.text(r'R$ 1.000,00'), findsNWidgets(2));
      expect(find.text(r'R$ 1.500,00'), findsNothing);
    });

    testWidgets('meta sem pendente não mostra a linha', (tester) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [testContribution(id: 'c1', minor: 100000)],
        ),
      );

      expect(find.byKey(const Key('goal_card_pending')), findsNothing);
    });
  });

  group('metas pausadas', () {
    testWidgets('saem da lista de metas e ganham seção própria', (
      tester,
    ) async {
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
              status: SavingsGoalStatus.paused,
            ),
          ],
          contributions: [testContribution(id: 'c1', minor: 324000)],
        ),
      );

      // Fora dos cards: pausada não é cobrada.
      expect(find.byKey(const Key('goal_card_goal-2')), findsNothing);
      // E alcançável: pausar não pode ser um esconder sem volta.
      expect(find.byKey(const Key('paused_goal_goal-2')), findsOneWidget);
      expect(find.text('1 meta pausada'), findsOneWidget);
      // O total conta só o que está ativo.
      expect(find.text('Guardado nesta meta'), findsOneWidget);
    });

    testWidgets('sem barra de progresso — é a cobrança que pausar cala', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [testGoal(status: SavingsGoalStatus.paused)],
        ),
      );

      expect(find.byType(SavingsProgress), findsNothing);
    });

    testWidgets('com todas pausadas, não cai no estado vazio', (tester) async {
      // O bug que isto guarda: `goalProgressList` filtra pausadas, então uma
      // checagem só nela mostraria "Nenhuma meta ainda" com metas existindo — e
      // sem nenhum caminho até elas.
      await pumpScreen(
        tester,
        const SavingsPage(),
        savingsRepository: FakeSavingsRepository(
          goals: [testGoal(status: SavingsGoalStatus.paused)],
        ),
      );

      expect(find.text('Nenhuma meta ainda'), findsNothing);
      expect(find.byKey(const Key('all_goals_paused')), findsOneWidget);
      expect(find.byKey(const Key('paused_goal_goal-1')), findsOneWidget);
      // Sem momento alto: não há meta ativa cujo total mostrar.
      expect(find.byType(BalanceHeader), findsNothing);
    });
  });
}
