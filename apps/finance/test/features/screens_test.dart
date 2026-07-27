import 'package:design_system/design_system.dart';
import 'package:finance/features/home/presentation/space_home_page.dart';
import 'package:finance/features/shell/presentation/app_shell.dart';
import 'package:finance/features/spaces/presentation/spaces_page.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/presentation/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

void main() {
  group('monthLabel', () {
    test('mês corrente aparece sem o ano', () {
      expect(
        monthLabel(DateTime(2026, 7), today: DateTime(2026, 7, 27)),
        'julho',
      );
    });

    test('outro ano ganha o ano', () {
      expect(
        monthLabel(DateTime(2025, 3), today: DateTime(2026, 7, 27)),
        'março de 2025',
      );
    });

    test('cobre os doze meses', () {
      final today = DateTime(2026, 7, 27);
      for (var m = 1; m <= 12; m++) {
        expect(monthLabel(DateTime(2026, m), today: today), isNotEmpty);
      }
    });
  });

  group('SpaceHomePage', () {
    testWidgets('espera a sincronização quando não há espaço', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        spaces: [],
        settle: false,
      );

      expect(find.text('Sincronizando seus dados…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('mostra o nome do espaço ativo', (tester) async {
      await pumpScreen(tester, const SpaceHomePage());

      expect(find.byKey(const Key('active_space_name')), findsOneWidget);
      expect(find.text('Pessoal'), findsOneWidget);
    });

    testWidgets('o saldo é o momento alto, em 40px', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 14280)],
      );

      final balance = tester.widget<Text>(find.text(r'-R$ 142,80'));
      expect(balance.style?.fontSize, 40);
    });

    testWidgets('sem transações mostra o estado vazio com ação', (
      tester,
    ) async {
      await pumpScreen(tester, const SpaceHomePage());

      expect(find.textContaining('Nenhum gasto em'), findsOneWidget);
      expect(find.text('Registrar gasto'), findsOneWidget);
    });

    testWidgets('com transações mostra atividade recente e "Ver tudo"', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 14280)],
      );

      expect(find.text('Atividade recente'), findsOneWidget);
      expect(find.text('Ver tudo'), findsOneWidget);
      expect(find.byType(TransactionTile), findsOneWidget);
    });

    testWidgets('limita a atividade recente a três linhas', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [
          for (var i = 0; i < 6; i++)
            testTransaction(minor: 1000 + i, id: 'tx-$i'),
        ],
      );

      expect(find.byType(TransactionTile), findsNWidgets(3));
    });

    testWidgets('mostra o orçamento quando existe', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 84210)],
        budgets: [testBudget()],
      );

      expect(find.text('Orçamento do mês'), findsOneWidget);
      expect(find.byType(BudgetProgress), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
    });

    testWidgets('sem orçamento não mostra a seção', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 100)],
      );

      expect(find.text('Orçamento do mês'), findsNothing);
    });

    testWidgets('"Ver tudo" navega para a lista do mês', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 14280)],
      );

      await tester.tap(find.text('Ver tudo'));
      await tester.pumpAndSettle();

      expect(find.byType(TransactionsPage), findsOneWidget);
    });

    testWidgets('o passo de mês está disponível', (tester) async {
      await pumpScreen(tester, const SpaceHomePage());

      expect(find.byKey(const Key('previous_month')), findsOneWidget);
      expect(find.byKey(const Key('next_month')), findsOneWidget);

      await tester.tap(find.byKey(const Key('previous_month')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza no tema escuro sem estourar layout', (tester) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 14280)],
        budgets: [testBudget()],
        dark: true,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('TransactionsPage', () {
    testWidgets('mostra o resumo de entradas e saídas', (tester) async {
      await pumpScreen(
        tester,
        const TransactionsPage(),
        wrapInScaffold: false,
        transactions: [
          testTransaction(minor: 14280),
          testTransaction(
            minor: 540000,
            type: TransactionType.income,
            id: 'tx-2',
          ),
        ],
      );

      expect(find.text('Entradas'), findsOneWidget);
      expect(find.text('Saídas'), findsOneWidget);
      expect(find.text('+5.400,00'), findsWidgets);
    });

    testWidgets('lista todas as transações do mês', (tester) async {
      await pumpScreen(
        tester,
        const TransactionsPage(),
        wrapInScaffold: false,
        transactions: [
          for (var i = 0; i < 5; i++)
            testTransaction(minor: 1000 + i, id: 'tx-$i'),
        ],
      );

      expect(find.byType(TransactionTile), findsNWidgets(5));
    });

    testWidgets('vazio mostra estado com ação', (tester) async {
      await pumpScreen(
        tester,
        const TransactionsPage(),
        wrapInScaffold: false,
      );

      expect(find.textContaining('Nenhum lançamento em'), findsOneWidget);
      expect(find.text('Registrar gasto'), findsOneWidget);
    });

    testWidgets('troca de mês pelo cabeçalho', (tester) async {
      await pumpScreen(
        tester,
        const TransactionsPage(),
        wrapInScaffold: false,
      );

      await tester.tap(find.byKey(const Key('list_previous_month')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza no tema escuro', (tester) async {
      await pumpScreen(
        tester,
        const TransactionsPage(),
        wrapInScaffold: false,
        transactions: [testTransaction(minor: 14280)],
        dark: true,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('SpacesPage', () {
    testWidgets('lista o espaço e marca o ativo', (tester) async {
      await pumpScreen(tester, const SpacesPage());

      expect(find.text('Espaços'), findsOneWidget);
      expect(find.text('Pessoal'), findsOneWidget);
      expect(find.text('Só seu'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('espera enquanto não sincronizou', (tester) async {
      await pumpScreen(
        tester,
        const SpacesPage(),
        spaces: [],
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('explica que espaços compartilhados vêm depois', (
      tester,
    ) async {
      await pumpScreen(tester, const SpacesPage());

      expect(find.text('Dividir ou somar com alguém'), findsOneWidget);
    });
  });

  group('AppShell', () {
    testWidgets('abre na aba Início com a bottom nav', (tester) async {
      await pumpScreen(tester, const AppShell(), wrapInScaffold: false);

      expect(find.byType(AppBottomNav), findsOneWidget);
      expect(find.byType(SpaceHomePage), findsOneWidget);
    });

    testWidgets('troca de aba', (tester) async {
      await pumpScreen(tester, const AppShell(), wrapInScaffold: false);

      await tester.tap(find.text('Espaços'));
      await tester.pumpAndSettle();

      // IndexedStack mantém as duas montadas; a de Espaços fica visível.
      expect(find.byType(SpacesPage), findsOneWidget);
    });

    testWidgets('as abas futuras avisam o que vem', (tester) async {
      await pumpScreen(tester, const AppShell(), wrapInScaffold: false);

      await tester.tap(find.text('Social'));
      await tester.pumpAndSettle();

      expect(find.byType(AppEmptyState), findsWidgets);
    });

    testWidgets('a ação central abre o registro rápido', (tester) async {
      await pumpScreen(tester, const AppShell(), wrapInScaffold: false);

      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pumpAndSettle();

      expect(find.text('Salvar'), findsOneWidget);
      expect(find.byKey(const Key('quick_entry_amount')), findsOneWidget);
    });
  });
}
