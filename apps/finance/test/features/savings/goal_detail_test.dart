import 'package:design_system/design_system.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:finance/features/savings/presentation/goal_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
// Emprestado em vez de copiado: `tapVisible` já existe em quatro arquivos de
// teste, e uma quinta cópia engordaria o débito de duplicação em vez de usá-la.
// Mesmo padrão do `transaction_edit_sheet_test.dart`, que importa o
// `RecordingTransactionsRepository` do teste do controller.
import 'goal_form_test.dart' show tapVisible;

void main() {
  Future<void> pumpDetail(
    WidgetTester tester, {
    required FakeSavingsRepository savings,
    String goalId = 'goal-1',
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      GoalDetailPage(goalId: goalId),
      savingsRepository: savings,
      accounts: [testAccount(name: 'Poupança Nubank')],
      // A página traz Scaffold próprio.
      wrapInScaffold: false,
    );
  }

  group('momento alto', () {
    testWidgets('abre pelo que já foi guardado, não pelo que falta', (
      tester,
    ) async {
      // A meta existe para dar visibilidade a um hábito; abrir pelo que falta
      // transformaria progresso em dívida.
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [testContribution(minor: 324000)],
        ),
      );

      final hero = tester.widget<MoneyText>(
        find
            .byWidgetPredicate(
              (w) => w is MoneyText && w.size == MoneySize.balance,
            )
            .first,
      );

      expect(hero.amount.amountMinor, 324000);
      expect(find.textContaining(r'de R$ 8.000,00 · 41%'), findsOneWidget);
    });
  });

  group('projeção', () {
    testWidgets('diz o ritmo, a data projetada e quanto falta por mês', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(
          goals: [
            testGoal(
              targetAmountMinor: 100000,
              targetDate: DateTime(2026, 10),
              createdAt: DateTime(2026, 4),
              linkedAccountId: 'acc-1',
            ),
          ],
          contributions: [testContribution(minor: 40000)],
        ),
      );

      final projection = tester.widget<Text>(
        find.byKey(const Key('goal_projection')),
      );
      expect(projection.data, contains(r'R$ 100,00 por mês'));

      final required = tester.widget<Text>(
        find.byKey(const Key('goal_required_monthly')),
      );
      expect(required.data, contains(r'R$ 200,00 por mês'));

      expect(find.textContaining('Guardando em'), findsOneWidget);
      expect(find.textContaining('Poupança Nubank'), findsOneWidget);
    });

    testWidgets('sem aporte nenhum, não inventa projeção', (tester) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(goals: [testGoal()]),
      );

      expect(find.byKey(const Key('goal_projection')), findsNothing);
    });
  });

  group('contribuições', () {
    testWidgets('lista o histórico com valor e origem', (tester) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [
            testContribution(
              id: 'c1',
              minor: 40000,
              contributedAt: DateTime(2026, 7, 18),
            ),
          ],
        ),
      );

      expect(find.text('Guardei'), findsOneWidget);
      expect(find.textContaining('manual'), findsOneWidget);
      expect(find.text('2 no total'), findsNothing);
      expect(find.text('1 no total'), findsOneWidget);
    });

    testWidgets('sem contribuição, explica o que fazer', (tester) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(goals: [testGoal()]),
      );

      expect(
        find.byKey(const Key('goal_no_contributions')),
        findsOneWidget,
      );
    });

    testWidgets('detecção pendente pede confirmação e não conta ainda', (
      tester,
    ) async {
      final savings = FakeSavingsRepository(
        goals: [testGoal(targetAmountMinor: 100000)],
        contributions: [
          testContribution(id: 'confirmada', minor: 20000),
          testContribution(
            id: 'pendente',
            minor: 30000,
            source: ContributionSource.openFinance,
            isConfirmed: false,
          ),
        ],
      );
      await pumpDetail(tester, savings: savings);

      // O valor pendente não entra no número grande (RN-3.3).
      final hero = tester.widget<MoneyText>(
        find
            .byWidgetPredicate(
              (w) => w is MoneyText && w.size == MoneySize.balance,
            )
            .first,
      );
      expect(hero.amount.amountMinor, 20000);

      expect(find.textContaining('detectada'), findsOneWidget);

      final confirm = find.byKey(const Key('confirm_contribution_pendente'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(savings.confirmed, ['pendente']);
    });
  });

  group('ações', () {
    testWidgets('o rodapé fixo carrega a única ação da tela', (tester) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(goals: [testGoal()]),
      );

      final action = find.byKey(const Key('add_contribution'));
      expect(action, findsOneWidget);
      // Rodapé fixo: a ação não depende de rolar até o fim da lista.
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(844));
    });

    testWidgets('abre a folha de guardar valor', (tester) async {
      final savings = FakeSavingsRepository(goals: [testGoal()]);
      await pumpDetail(tester, savings: savings);

      await tester.tap(find.byKey(const Key('add_contribution')));
      await tester.pumpAndSettle();

      expect(find.text('Guardei um valor'), findsWidgets);
      expect(find.byKey(const Key('contribution_save')), findsOneWidget);
    });

    testWidgets('registra o valor guardado', (tester) async {
      final savings = FakeSavingsRepository(goals: [testGoal()]);
      await pumpDetail(tester, savings: savings);

      await tester.tap(find.byKey(const Key('add_contribution')));
      await tester.pumpAndSettle();

      for (final digit in [5, 0, 0, 0, 0]) {
        await tester.tap(find.text('$digit').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('contribution_save')));
      await tester.pumpAndSettle();

      expect(savings.addedContributions, hasLength(1));
      expect(savings.addedContributions.single.amount.amountMinor, 50000);
      expect(savings.addedContributions.single.goalId, 'goal-1');
    });

    testWidgets('com uma conta só, ela vai no lançamento sem custar um toque', (
      tester,
    ) async {
      // `pumpDetail` monta o espaço com uma conta. Mesmo padrão do registro
      // rápido: perguntar custaria um toque para uma resposta já conhecida.
      final savings = FakeSavingsRepository(goals: [testGoal()]);
      await pumpDetail(tester, savings: savings);

      await tester.tap(find.byKey(const Key('add_contribution')));
      await tester.pumpAndSettle();

      expect(find.text('Saiu de'), findsOneWidget);

      for (final digit in [5, 0, 0, 0, 0]) {
        await tester.tap(find.text('$digit').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('contribution_save')));
      await tester.pumpAndSettle();

      expect(savings.addedAccountIds, ['acc-1']);
    });
  });

  group('remover contribuição', () {
    testWidgets('a dica diz que o toque remove', (tester) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [testContribution(minor: 50000)],
        ),
      );

      // Toque destrutivo sem dica ninguém descobre — e quem descobrisse por
      // acidente levaria um susto.
      expect(find.byKey(const Key('goal_contributions_hint')), findsOneWidget);
    });

    testWidgets('confirmar remove, e o diálogo avisa do lançamento', (
      tester,
    ) async {
      final savings = FakeSavingsRepository(
        goals: [testGoal()],
        contributions: [
          testContribution(minor: 50000, transactionId: 'tx-savings'),
        ],
      );
      await pumpDetail(tester, savings: savings);

      await tapVisible(
        tester,
        find.byKey(const Key('contribution_row_contrib-1')),
      );

      // A cópia nomeia o efeito colateral, como nos outros três diálogos.
      expect(find.textContaining('sai do extrato junto'), findsOneWidget);
      expect(savings.deletedContributions, isEmpty);

      await tapVisible(
        tester,
        find.byKey(const Key('confirm_delete_contribution')),
      );

      expect(savings.deletedContributions, ['contrib-1']);
    });

    testWidgets('cancelar não remove nada', (tester) async {
      final savings = FakeSavingsRepository(
        goals: [testGoal()],
        contributions: [
          testContribution(minor: 50000, transactionId: 'tx-savings'),
        ],
      );
      await pumpDetail(tester, savings: savings);

      await tapVisible(
        tester,
        find.byKey(const Key('contribution_row_contrib-1')),
      );
      await tapVisible(tester, find.text('Cancelar'));

      expect(savings.deletedContributions, isEmpty);
    });

    testWidgets(
      'sem lançamento ligado, o diálogo não promete mexer no extrato',
      (tester) async {
        // É o estado de toda linha anterior à migration 20260728000822:
        // prometer que "o lançamento sai junto" ali seria mentira.
        final savings = FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [testContribution(minor: 50000)],
        );
        await pumpDetail(tester, savings: savings);

        await tapVisible(
          tester,
          find.byKey(const Key('contribution_row_contrib-1')),
        );

        expect(find.textContaining('sai do extrato junto'), findsNothing);
        expect(find.textContaining('o extrato não muda'), findsOneWidget);
      },
    );
  });

  group('meta que deixou de existir', () {
    testWidgets('sai em vez de estourar', (tester) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(),
        goalId: 'nao-existe',
      );

      expect(find.text('Meta não encontrada'), findsOneWidget);
    });
  });

  group('meta pausada', () {
    testWidgets('mostra o guardado e cala o que cobra', (tester) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(
          goals: [
            testGoal(
              status: SavingsGoalStatus.paused,
              targetDate: DateTime(2026, 12),
            ),
          ],
          contributions: [testContribution(minor: 324000)],
        ),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('goal_status_line'))).data,
        'Pausada · retome em Editar',
      );

      // Sem marca de ritmo: o tick diz "o prazo esperava você aqui".
      final bar = tester.widget<SavingsProgress>(find.byType(SavingsProgress));
      expect(bar.paceRatio, isNull);
      // A barra fica: quanto já foi guardado é informação, não pressão.
      expect(bar.ratio, greaterThan(0));

      // Sem projeção: ela pressupõe um ritmo que a meta pausada não tem.
      expect(find.byKey(const Key('goal_projection')), findsNothing);
      expect(find.byKey(const Key('goal_required_monthly')), findsNothing);
    });

    testWidgets('segue alcançável e ainda aceita guardar valor', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(
          goals: [testGoal(status: SavingsGoalStatus.paused)],
        ),
      );

      // Pausar cala a cobrança, não tranca a porta.
      expect(find.byKey(const Key('add_contribution')), findsOneWidget);
      expect(find.byKey(const Key('goal_edit')), findsOneWidget);
    });
  });

  group('meta percentual sem base', () {
    testWidgets('não mostra percentual junto do alvo', (tester) async {
      await pumpDetail(
        tester,
        savings: FakeSavingsRepository(
          goals: [
            testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
          ],
        ),
      );

      expect(find.text('sem base neste mês'), findsOneWidget);
      expect(find.textContaining('· 0%'), findsNothing);
    });
  });
}
