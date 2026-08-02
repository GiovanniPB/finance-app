import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:finance/features/home/presentation/space_home_page.dart';
import 'package:finance/features/spaces/domain/space_member.dart';
import 'package:finance/features/transactions/domain/expense_split.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/presentation/transaction_edit_sheet.dart';
import 'package:finance/features/transactions/presentation/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import 'transaction_edit_controller_test.dart'
    show RecordingTransactionsRepository;

void main() {
  _splitSectionTests();

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

/// A seção "Dividido entre" (RN-2.1).
///
/// Metade destes testes verifica **ausência**: a seção não aparece em quatro
/// situações, e aparecer em qualquer uma delas é pior que não existir — um
/// controle que promete algo que o produto decidiu não ter.
void _splitSectionTests() {
  Transaction groupExpense({
    int minor = 24000,
    bool isShared = false,
    String? paidBy,
  }) => testTransaction(
    minor: minor,
    spaceId: 'space-2',
    isShared: isShared,
    paidBy: paidBy,
  );

  Future<FakeTransactionsRepository> pumpSplit(
    WidgetTester tester, {
    Transaction? transaction,
    List<SpaceMember>? members,
    List<ExpenseSplit> splits = const [],
  }) async {
    final tx = transaction ?? groupExpense();
    final repository = FakeTransactionsRepository([tx], splits: splits);
    await pumpScreen(
      tester,
      TransactionEditSheet(transaction: tx),
      spacesRepository: FakeSpacesRepository(
        [personalSpace(), testSharedSpace()],
        members:
            members ??
            [
              testMember(id: 'm-1', displayName: 'Giovanni'),
              testMember(
                id: 'm-2',
                userId: 'user-2',
                displayName: 'Ana Prado',
              ),
            ],
      ),
      transactionsRepository: repository,
      categories: [testCategory()],
    );
    return repository;
  }

  group('onde a seção não aparece', () {
    testWidgets('espaço pessoal', (tester) async {
      await pumpSplit(tester, transaction: testTransaction(minor: 24000));

      expect(find.text('Dividido entre'), findsNothing);
    });

    testWidgets('receita, mesmo em grupo', (tester) async {
      await pumpSplit(
        tester,
        transaction: testTransaction(
          minor: 24000,
          spaceId: 'space-2',
          type: TransactionType.income,
        ),
      );

      expect(find.text('Dividido entre'), findsNothing);
    });

    testWidgets('transferência, mesmo em grupo', (tester) async {
      await pumpSplit(
        tester,
        transaction: testTransaction(
          minor: 24000,
          spaceId: 'space-2',
          type: TransactionType.transfer,
        ),
      );

      expect(find.text('Dividido entre'), findsNothing);
    });

    // "Quem pagou" segue a mesma regra: fora de despesa de grupo o campo não
    // existe, em vez de existir com uma opção só.
    testWidgets('"Quem pagou" acompanha a seção', (tester) async {
      await pumpSplit(tester, transaction: testTransaction(minor: 24000));

      expect(find.text('Quem pagou'), findsNothing);
    });
  });

  group('quem pagou', () {
    testWidgets('sem escolha, quem lançou vem marcado', (tester) async {
      await pumpSplit(tester);

      expect(find.text('Quem pagou'), findsOneWidget);
      // Uma pílula por membro ativo, e a de quem lançou já selecionada —
      // `paid_by` nulo significa `created_by`, não "nenhum".
      expect(find.byKey(const Key('payer_user-1')), findsOneWidget);
      expect(find.byKey(const Key('payer_user-2')), findsOneWidget);
      expect(
        tester
            .widget<CategoryChip>(find.byKey(const Key('payer_user-1')))
            .isSelected,
        isTrue,
      );
      expect(
        tester
            .widget<CategoryChip>(find.byKey(const Key('payer_user-2')))
            .isSelected,
        isFalse,
      );
    });

    testWidgets('a minha pílula diz "Você", não o meu nome', (tester) async {
      await pumpSplit(tester);

      expect(
        tester
            .widget<CategoryChip>(find.byKey(const Key('payer_user-1')))
            .label,
        'Você',
      );
      expect(
        tester
            .widget<CategoryChip>(find.byKey(const Key('payer_user-2')))
            .label,
        'Ana Prado',
      );
    });

    testWidgets('o pagador gravado vem marcado ao abrir', (tester) async {
      await pumpSplit(tester, transaction: groupExpense(paidBy: 'user-2'));

      expect(
        tester
            .widget<CategoryChip>(find.byKey(const Key('payer_user-2')))
            .isSelected,
        isTrue,
      );
    });

    // Diferente do botão de dividir, a pílula não grava ao toque: o pagador é
    // campo do formulário e sobe no "Salvar", junto do resto.
    testWidgets('tocar não grava; salvar grava', (tester) async {
      final repository = await pumpSplit(tester);

      await tapVisible(tester, find.byKey(const Key('payer_user-2')));
      expect(repository.updates, isEmpty);

      await tapVisible(tester, find.text('Salvar'));

      expect(repository.updates, hasLength(1));
      expect(repository.updates.single.paidBy, 'user-2');
    });

    // O defeito gêmeo do que a fatia anterior encontrou: `is_shared` vinha da
    // entidade carregada ao abrir, e salvar apagava a marca. Aqui a folha manda
    // as duas coisas juntas, e as partes seguem de pé.
    testWidgets('trocar o pagador e salvar preserva a divisão', (tester) async {
      final repository = await pumpSplit(
        tester,
        transaction: groupExpense(isShared: true),
        splits: [
          for (final userId in ['user-1', 'user-2'])
            ExpenseSplit(
              id: 'split-$userId',
              transactionId: 'tx-1',
              spaceId: 'space-2',
              userId: userId,
              amount: const Money.fromMinor(12000),
              createdAt: testNow,
              updatedAt: testNow,
            ),
        ],
      );

      await tapVisible(tester, find.byKey(const Key('payer_user-2')));
      await tapVisible(tester, find.text('Salvar'));

      expect(repository.updates.single.paidBy, 'user-2');
      expect(repository.updates.single.isShared, isTrue);
      expect(repository.splits, hasLength(2));
    });
  });

  group('despesa de grupo ainda não dividida', () {
    testWidgets('oferece dividir igualmente, e nada mais', (tester) async {
      await pumpSplit(tester);

      expect(find.text('Dividido entre'), findsOneWidget);
      expect(find.byKey(const Key('transaction_split')), findsOneWidget);
      expect(find.byKey(const Key('transaction_unsplit')), findsNothing);
      expect(find.byKey(const Key('split_total')), findsNothing);
    });

    testWidgets('tocar divide entre os membros ativos', (tester) async {
      final repository = await pumpSplit(tester);

      await tapVisible(tester, find.byKey(const Key('transaction_split')));

      expect(repository.splitCalls, ['tx-1']);
      expect(find.byKey(const Key('split_user-1')), findsOneWidget);
      expect(find.byKey(const Key('split_user-2')), findsOneWidget);
    });
  });

  group('despesa já dividida', () {
    List<ExpenseSplit> equalSplits({int each = 12000}) => [
      for (final userId in ['user-1', 'user-2'])
        ExpenseSplit(
          id: 'split-$userId',
          transactionId: 'tx-1',
          spaceId: 'space-2',
          userId: userId,
          amount: Money.fromMinor(each),
          createdAt: testNow,
          updatedAt: testNow,
        ),
    ];

    testWidgets('mostra uma linha por pessoa, com o nome', (tester) async {
      await pumpSplit(
        tester,
        transaction: groupExpense(isShared: true),
        splits: equalSplits(),
      );

      expect(find.text('2 pessoas'), findsOneWidget);
      // A minha linha ganha o qualificador; a do outro é só o nome. A busca é
      // **dentro da linha**: "Quem pagou" mostra as mesmas pessoas logo acima,
      // e procurar na folha inteira acharia o nome duas vezes.
      expect(
        find.descendant(
          of: find.byKey(const Key('split_user-1')),
          matching: find.textContaining('Giovanni', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('split_user-2')),
          matching: find.text('Ana Prado'),
        ),
        findsOneWidget,
      );
    });

    // A linha existe para o rateio ser verificável sem confiar no código.
    testWidgets('a soma das partes aparece e fecha o total', (tester) async {
      await pumpSplit(
        tester,
        transaction: groupExpense(isShared: true),
        splits: equalSplits(),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('split_total'))).data,
        r'R$ 240,00',
      );
    });

    testWidgets('o centavo que sobra aparece na primeira parte', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        transaction: groupExpense(minor: 1000, isShared: true),
        splits: [
          ...equalSplits(each: 334).take(1),
          ...equalSplits(each: 333).skip(1),
        ],
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('split_total'))).data,
        r'R$ 6,67',
      );
    });

    testWidgets('desfazer chama o repositório', (tester) async {
      final repository = await pumpSplit(
        tester,
        transaction: groupExpense(isShared: true),
        splits: equalSplits(),
      );

      await tapVisible(tester, find.byKey(const Key('transaction_unsplit')));

      expect(repository.unsplitCalls, ['tx-1']);
    });

    // A parte permanece quando a pessoa sai: apagá-la reescreveria o passado.
    testWidgets('parte de quem saiu não vira linha em branco', (tester) async {
      await pumpSplit(
        tester,
        transaction: groupExpense(isShared: true),
        splits: equalSplits(),
        members: [
          testMember(id: 'm-1', displayName: 'Giovanni'),
        ],
      );

      expect(find.text('Quem saiu do espaço'), findsOneWidget);
    });

    testWidgets('membro sem nome cai no texto de antes', (tester) async {
      await pumpSplit(
        tester,
        transaction: groupExpense(isShared: true),
        splits: equalSplits(),
        members: [
          testMember(id: 'm-1'),
          testMember(id: 'm-2', userId: 'user-2'),
        ],
      );

      expect(find.textContaining('No espaço desde'), findsOneWidget);
    });
  });

  group('erro', () {
    testWidgets('falha ao dividir aparece na folha, sem fechar', (
      tester,
    ) async {
      final repository = await pumpSplit(tester);
      repository.splitFailure = const ValidationFailure(
        'Só despesa de um grupo pode ser dividida.',
      );

      await tapVisible(tester, find.byKey(const Key('transaction_split')));

      expect(
        find.byKey(const Key('transaction_split_error')),
        findsOneWidget,
      );
      expect(find.byType(TransactionEditSheet), findsOneWidget);
    });
  });
}
