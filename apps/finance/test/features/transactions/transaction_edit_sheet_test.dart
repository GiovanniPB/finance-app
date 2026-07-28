import 'package:design_system/design_system.dart';
import 'package:finance/features/home/presentation/space_home_page.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/presentation/transaction_edit_sheet.dart';
import 'package:finance/features/transactions/presentation/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import 'transaction_edit_controller_test.dart'
    show RecordingTransactionsRepository;

void main() {
  group('TransactionEditSheet', () {
    testWidgets('abre preenchida com o que está gravado', (tester) async {
      await pumpScreen(
        tester,
        // testTransaction descreve 'Mercado' por padrão.
        TransactionEditSheet(transaction: testTransaction(minor: 4250)),
        categories: [testCategory()],
      );

      expect(find.text('Editar lançamento'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '42,50',
      );
      expect(find.widgetWithText(TextField, 'Mercado'), findsOneWidget);
    });

    testWidgets('mostra a procedência do lançamento', (tester) async {
      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: testTransaction(minor: 100)),
      );

      expect(
        find.textContaining('Registrado manualmente'),
        findsOneWidget,
      );
    });

    testWidgets('despesa e receita aparecem como segmento', (tester) async {
      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: testTransaction(minor: 100)),
      );

      expect(find.byType(AppSegmentedControl), findsOneWidget);
      expect(find.text('Despesa'), findsOneWidget);
      expect(find.text('Receita'), findsOneWidget);
    });

    testWidgets('poupança não oferece troca de tipo', (tester) async {
      await pumpScreen(
        tester,
        TransactionEditSheet(
          transaction: testTransaction(
            minor: 100,
            type: TransactionType.savings,
          ),
        ),
      );

      // Um segmento de duas posições não representa poupança; trocá-la por
      // despesa perderia o que a distingue.
      expect(find.byType(AppSegmentedControl), findsNothing);
      expect(find.text('Poupança'), findsOneWidget);
    });

    testWidgets('apagar todo o valor desabilita Salvar', (tester) async {
      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: testTransaction(minor: 42)),
      );

      await tapVisible(tester, find.byIcon(Icons.backspace_outlined));
      await tapVisible(tester, find.byIcon(Icons.backspace_outlined));

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isFalse,
      );
    });

    testWidgets('salvar persiste a edição e fecha', (tester) async {
      final repo = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: testTransaction(minor: 4250)),
        transactionsRepository: repo,
        categories: [testCategory()],
      );

      await tapVisible(tester, find.text('9'));
      await tapVisible(tester, find.text('Salvar'));

      expect(repo.updated?.amount.amountMinor, -42509);
    });

    testWidgets('excluir pede confirmação antes de apagar', (tester) async {
      final repo = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        TransactionEditSheet(
          transaction: testTransaction(minor: 100, id: 'tx-42'),
        ),
        transactionsRepository: repo,
      );

      await tapVisible(tester, find.byKey(const Key('transaction_delete')));

      expect(find.text('Excluir lançamento?'), findsOneWidget);
      expect(find.text('Isso não pode ser desfeito.'), findsOneWidget);
      // Ainda nada apagado: a confirmação é o gate.
      expect(repo.deleted, isEmpty);
    });

    testWidgets('cancelar a confirmação não apaga nada', (tester) async {
      final repo = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: testTransaction(minor: 100)),
        transactionsRepository: repo,
      );

      await tapVisible(tester, find.byKey(const Key('transaction_delete')));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.deleted, isEmpty);
      expect(find.text('Editar lançamento'), findsOneWidget);
    });

    testWidgets('confirmar exclui o lançamento', (tester) async {
      final repo = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        TransactionEditSheet(
          transaction: testTransaction(minor: 100, id: 'tx-42'),
        ),
        transactionsRepository: repo,
      );

      await tapVisible(tester, find.byKey(const Key('transaction_delete')));
      await tester.tap(find.byKey(const Key('confirm_delete')));
      await tester.pumpAndSettle();

      expect(repo.deleted, ['tx-42']);
    });

    testWidgets('tocar a data abre o seletor', (tester) async {
      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: testTransaction(minor: 100)),
      );

      await tapVisible(tester, find.byKey(const Key('transaction_date')));

      expect(find.text('Data do lançamento'), findsOneWidget);
    });

    testWidgets('as ações ficam num rodapé fixo, sem precisar rolar', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: testTransaction(minor: 4250)),
        transactionsRepository: RecordingTransactionsRepository(),
        categories: [testCategory()],
      );

      // Sem ensureVisible: Salvar e Excluir precisam estar visíveis de saída.
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('funciona no tema escuro sem overflow', (tester) async {
      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: testTransaction(minor: 4250)),
        categories: [testCategory()],
        dark: true,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('entrada pela lista', () {
    testWidgets('tocar uma linha da lista do mês abre a edição', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const TransactionsPage(),
        wrapInScaffold: false,
        // A descrição padrão de testTransaction é 'Mercado'.
        transactions: [testTransaction(minor: 4250)],
        categories: [testCategory()],
      );

      await tester.tap(find.text('Mercado'));
      await tester.pumpAndSettle();

      expect(find.text('Editar lançamento'), findsOneWidget);
    });

    testWidgets('tocar a atividade recente da home abre a edição', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SpaceHomePage(),
        transactions: [testTransaction(minor: 4250, description: 'Padaria')],
        categories: [testCategory()],
      );

      await tester.tap(find.text('Padaria'));
      await tester.pumpAndSettle();

      expect(find.text('Editar lançamento'), findsOneWidget);
    });
  });

  group('lançamento que pertence a uma meta', () {
    Transaction savingsTransaction() => testTransaction(
      id: 'tx-savings',
      minor: 50000,
      type: TransactionType.savings,
      categoryId: null,
      description: 'Viagem ao Chile',
    );

    testWidgets('não é editável aqui, e aponta para a meta', (tester) async {
      final transaction = savingsTransaction();

      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: transaction),
        transactions: [transaction],
        savingsRepository: FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [
            testContribution(minor: 50000, transactionId: 'tx-savings'),
          ],
        ),
      );

      expect(
        find.byKey(const Key('transaction_owned_by_goal')),
        findsOneWidget,
      );
      expect(find.text('Abrir Viagem ao Chile'), findsOneWidget);

      // Nada de editar: valor e data pertencem à contribuição, e mudá-los aqui
      // faria as duas faces do mesmo evento discordarem.
      expect(find.byType(AmountKeypad), findsNothing);
      expect(find.text('Salvar'), findsNothing);
      // Nem de excluir: sobraria contribuição contando dinheiro que o extrato
      // não explica.
      expect(find.byKey(const Key('transaction_delete')), findsNothing);
    });

    testWidgets('o que trava é o vínculo, não o tipo', (tester) async {
      // Um lançamento `savings` sem contribuição ligada (o que a ingestão do
      // Open Finance pode produzir) segue editável: não há segunda face para
      // desincronizar.
      final transaction = savingsTransaction();

      await pumpScreen(
        tester,
        TransactionEditSheet(transaction: transaction),
        transactions: [transaction],
        savingsRepository: FakeSavingsRepository(goals: [testGoal()]),
      );

      expect(find.byKey(const Key('transaction_owned_by_goal')), findsNothing);
      expect(find.byKey(const Key('transaction_delete')), findsOneWidget);
    });
  });
}
