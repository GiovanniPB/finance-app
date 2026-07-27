import 'package:design_system/design_system.dart';
import 'package:finance/features/budgets/presentation/budget_form_sheet.dart';
import 'package:finance/features/budgets/presentation/budgets_page.dart';
import 'package:finance/features/home/presentation/space_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  group('BudgetsPage', () {
    testWidgets('sem limite convida a definir o primeiro', (tester) async {
      await pumpScreen(
        tester,
        const BudgetsPage(),
        wrapInScaffold: false,
      );

      expect(find.textContaining('Nenhum limite em'), findsOneWidget);
      expect(find.text('Definir limite'), findsOneWidget);
      // Sem limite algum, o FAB seria um segundo caminho competindo com o
      // convite do estado vazio.
      expect(find.byKey(const Key('new_budget')), findsNothing);
    });

    testWidgets('lista o limite do mês com categoria e progresso', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const BudgetsPage(),
        wrapInScaffold: false,
        categories: [testCategory()],
        budgets: [testBudget()],
        transactions: [testTransaction(minor: 84210)],
      );

      expect(find.text('Alimentação'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.byKey(const Key('new_budget')), findsOneWidget);
    });

    testWidgets('mostra quanto ainda cabe', (tester) async {
      await pumpScreen(
        tester,
        const BudgetsPage(),
        wrapInScaffold: false,
        budgets: [testBudget()],
        transactions: [testTransaction(minor: 84210)],
      );

      expect(find.text(r'Faltam R$ 357,90'), findsOneWidget);
    });

    testWidgets('estourado diz o quanto passou', (tester) async {
      await pumpScreen(
        tester,
        const BudgetsPage(),
        wrapInScaffold: false,
        budgets: [testBudget(limitMinor: 30000)],
        transactions: [testTransaction(minor: 31840)],
      );

      expect(find.text(r'Estourou em R$ 18,40'), findsOneWidget);
      expect(find.text('106%'), findsOneWidget);
    });

    testWidgets('tocar a linha abre a folha em modo edição', (tester) async {
      await pumpScreen(
        tester,
        const BudgetsPage(),
        wrapInScaffold: false,
        categories: [testCategory()],
        budgets: [testBudget()],
      );

      await tester.tap(find.byType(BudgetUsageCard));
      await tester.pumpAndSettle();

      expect(find.text('Editar orçamento'), findsOneWidget);
      // Preenchida com o limite atual: 1.200,00.
      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '1.200,00',
      );
      expect(find.byKey(const Key('budget_form_remove')), findsOneWidget);
    });

    testWidgets('o FAB abre a folha em modo novo', (tester) async {
      await pumpScreen(
        tester,
        const BudgetsPage(),
        wrapInScaffold: false,
        budgets: [testBudget()],
      );

      await tester.tap(find.byKey(const Key('new_budget')));
      await tester.pumpAndSettle();

      expect(find.text('Novo orçamento'), findsOneWidget);
      expect(find.byKey(const Key('budget_form_remove')), findsNothing);
    });

    testWidgets('funciona no tema escuro', (tester) async {
      await pumpScreen(
        tester,
        const BudgetsPage(),
        wrapInScaffold: false,
        budgets: [testBudget()],
        transactions: [testTransaction(minor: 84210)],
        dark: true,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(BudgetUsageCard), findsOneWidget);
    });
  });

  group('BudgetFormSheet', () {
    testWidgets('novo começa zerado e com Definir limite desabilitado', (
      tester,
    ) async {
      await pumpScreen(tester, const BudgetFormSheet());

      expect(find.text('Novo orçamento'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '0,00',
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, isFalse);
    });

    testWidgets('diz de que mês em diante o limite vale', (tester) async {
      await pumpScreen(tester, const BudgetFormSheet());

      expect(
        find.textContaining('Limite mensal a partir de'),
        findsOneWidget,
      );
    });

    testWidgets('digitar valor e escolher categoria habilita salvar', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const BudgetFormSheet(),
        categories: [testCategory()],
      );

      await tester.tap(find.text('5'));
      await tester.tap(find.text('0'));
      await tester.tap(find.text('0'));
      await tester.tap(find.text('Alimentação'));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '5,00',
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isTrue,
      );
    });

    testWidgets('ao criar, esconde categoria que já tem limite no mês', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const BudgetFormSheet(),
        categories: [
          testCategory(),
          testCategory(id: 'cat-2', name: 'Transporte'),
        ],
        // testBudget orça cat-1, que é a categoria de testCategory.
        budgets: [testBudget()],
      );

      expect(find.text('Alimentação'), findsNothing);
      expect(find.text('Transporte'), findsOneWidget);
    });

    testWidgets('sem categoria disponível explica por quê', (tester) async {
      await pumpScreen(
        tester,
        const BudgetFormSheet(),
        categories: [testCategory()],
        budgets: [testBudget()],
      );

      expect(
        find.text('Todas as categorias já têm limite neste mês.'),
        findsOneWidget,
      );
    });

    testWidgets('editando, a categoria é fixa e não vira chip', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        BudgetFormSheet(editing: testBudget(limitMinor: 45000)),
        categories: [testCategory()],
      );

      expect(find.text('Editar orçamento'), findsOneWidget);
      expect(find.text('Categoria: '), findsOneWidget);
      expect(find.byType(CategoryChip), findsNothing);
      expect(find.text('Salvar limite'), findsOneWidget);
    });

    testWidgets('funciona no tema escuro sem overflow', (tester) async {
      await pumpScreen(
        tester,
        BudgetFormSheet(editing: testBudget()),
        categories: [testCategory()],
        dark: true,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('SpaceHomePage — entrada de orçamento', () {
    testWidgets('com limite, a seção tem ação de gerenciar', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        budgets: [testBudget()],
        transactions: [testTransaction(minor: 5000)],
      );

      expect(find.text('Orçamento do mês'), findsOneWidget);
      expect(find.text('Gerenciar'), findsOneWidget);
      expect(find.byKey(const Key('budget_invite')), findsNothing);
    });

    testWidgets('quem já registra e não orçou recebe convite', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 5000)],
      );

      expect(find.byKey(const Key('budget_invite')), findsOneWidget);
      expect(find.text('Definir um limite'), findsOneWidget);
    });

    testWidgets('sem transação alguma o convite não aparece', (tester) async {
      await pumpScreen(tester, const SpaceHomePage());

      // A home já é um estado vazio pedindo o primeiro gasto; dois convites
      // competindo diluiriam os dois.
      expect(find.byKey(const Key('budget_invite')), findsNothing);
      expect(find.text('Registrar gasto'), findsOneWidget);
    });

    testWidgets('o convite abre a folha de novo orçamento', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 5000)],
      );

      await tester.tap(find.byKey(const Key('budget_invite')));
      await tester.pumpAndSettle();

      expect(find.text('Novo orçamento'), findsOneWidget);
    });
  });
}
