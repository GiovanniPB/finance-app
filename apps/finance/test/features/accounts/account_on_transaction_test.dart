import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/accounts/presentation/account_picker.dart';
import 'package:finance/features/accounts/presentation/accounts_providers.dart';
import 'package:finance/features/spaces/presentation/spaces_providers.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/domain/transactions_repository.dart';
import 'package:finance/features/transactions/presentation/quick_entry_sheet.dart';
import 'package:finance/features/transactions/presentation/transaction_edit_sheet.dart';
import 'package:finance/features/transactions/presentation/transaction_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Repositório de transações que guarda a conta do que foi gravado.
class RecordingTransactionsRepository implements TransactionsRepository {
  /// Conta de cada `create`, na ordem — `null` quando o lançamento foi sem
  /// conta, que é o que este arquivo passa a maior parte do tempo checando.
  final List<String?> createdAccountIds = [];

  final List<Transaction> updated = [];

  @override
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) => Stream.value(const []);

  @override
  Future<Result<Transaction, Failure>> create({
    required String spaceId,
    required TransactionType type,
    required Money amount,
    required DateTime occurredAt,
    String? accountId,
    String? categoryId,
    String? description,
    bool isShared = false,
  }) async {
    createdAccountIds.add(accountId);
    return Ok(
      testTransaction(minor: amount.amountMinor.abs(), accountId: accountId),
    );
  }

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async {
    updated.add(transaction);
    return Ok(transaction);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async => const Ok(null);
}

/// Abre a folha de edição de [transaction] a partir de um botão, para o teste
/// exercitar o fluxo real (`show`).
Widget editOpener(Transaction transaction) => Builder(
  builder: (context) => Center(
    child: ElevatedButton(
      onPressed: () => TransactionEditSheet.show(context, transaction),
      child: const Text('abrir'),
    ),
  ),
);

void main() {
  group('AccountPicker', () {
    testWidgets('sem conta cadastrada, não mostra nem o rótulo', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        AccountPicker(accounts: const [], selectedId: null, onSelected: (_) {}),
      );

      expect(find.text('Conta'), findsNothing);
    });

    testWidgets('mostra um chip por conta', (tester) async {
      await pumpScreen(
        tester,
        AccountPicker(
          accounts: [
            testAccount(),
            testAccount(id: 'acc-2', name: 'Cartão'),
          ],
          selectedId: 'acc-2',
          onSelected: (_) {},
        ),
      );

      expect(find.text('Conta'), findsOneWidget);
      expect(find.text('Conta corrente'), findsOneWidget);
      expect(find.text('Cartão'), findsOneWidget);
    });

    testWidgets('tocar na conta marcada desmarca', (tester) async {
      String? selected = 'acc-1';
      await pumpScreen(
        tester,
        AccountPicker(
          accounts: [testAccount()],
          selectedId: 'acc-1',
          onSelected: (id) => selected = id,
        ),
      );

      await tester.tap(find.byKey(const Key('account_chip_acc-1')));
      await tester.pump();

      expect(selected, isNull);
    });
  });

  group('Registro rápido', () {
    Future<void> fillAndSave(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(InkWell, '5'));
      await tester.pump();
      await tester.tap(find.text('Alimentação'));
      await tester.pump();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
    }

    testWidgets('sem conta cadastrada, o campo nem aparece', (tester) async {
      await pumpScreen(tester, const QuickEntrySheet());

      expect(find.byType(AccountPicker), findsNothing);
    });

    // O padrão que preserva a promessa dos 30 segundos: com uma conta só, ela
    // já vem marcada e não custa toque nenhum.
    testWidgets('com uma conta só, ela já vem escolhida', (tester) async {
      final repository = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        const QuickEntrySheet(),
        accounts: [testAccount()],
        transactionsRepository: repository,
      );

      await fillAndSave(tester);

      expect(repository.createdAccountIds, ['acc-1']);
    });

    testWidgets('tirar a conta única de propósito é respeitado', (
      tester,
    ) async {
      final repository = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        const QuickEntrySheet(),
        accounts: [testAccount()],
        transactionsRepository: repository,
      );

      await tapVisible(tester, find.byKey(const Key('account_chip_acc-1')));
      await fillAndSave(tester);

      expect(repository.createdAccountIds, [null]);
    });

    testWidgets('com duas contas, nenhuma vem escolhida', (tester) async {
      final repository = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        const QuickEntrySheet(),
        accounts: [
          testAccount(),
          testAccount(id: 'acc-2', name: 'Cartão'),
        ],
        transactionsRepository: repository,
      );

      await fillAndSave(tester);

      expect(repository.createdAccountIds, [null]);
    });
  });

  group('Edição de lançamento', () {
    testWidgets('não atribui conta sozinha a lançamento antigo', (
      tester,
    ) async {
      final repository = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        editOpener(testTransaction(minor: 1000)),
        accounts: [testAccount()],
        transactionsRepository: repository,
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(repository.updated.single.accountId, isNull);
    });

    testWidgets('escolher conta grava no lançamento', (tester) async {
      final repository = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        editOpener(testTransaction(minor: 1000)),
        accounts: [testAccount()],
        transactionsRepository: repository,
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('account_chip_acc-1')));
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(repository.updated.single.accountId, 'acc-1');
    });

    testWidgets('tirar a conta de um lançamento persiste a remoção', (
      tester,
    ) async {
      final repository = RecordingTransactionsRepository();
      await pumpScreen(
        tester,
        editOpener(testTransaction(minor: 1000, accountId: 'acc-1')),
        accounts: [testAccount()],
        transactionsRepository: repository,
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('account_chip_acc-1')));
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(repository.updated.single.accountId, isNull);
    });
  });

  group('accountLabelsProvider', () {
    Future<Map<String, String>> labelsFor(List<String> names) async {
      final container = ProviderContainer(
        overrides: [
          accountsRepositoryProvider.overrideWithValue(
            FakeAccountsRepository([
              for (var i = 0; i < names.length; i++)
                testAccount(id: 'acc-${i + 1}', name: names[i]),
            ]),
          ),
          spacesRepositoryProvider.overrideWithValue(
            FakeSpacesRepository([personalSpace()]),
          ),
        ],
      );
      addTearDown(container.dispose);
      // `listen` segura os providers (são autoDispose) e o `await` espera cada
      // stream emitir. A ordem importa: sem espaço ativo, `spaceAccounts`
      // devolve lista vazia, e o teste passaria por acidente em todo caso.
      for (final subscription in [
        container.listen(spacesProvider, (_, _) {}),
        container.listen(spaceAccountsProvider, (_, _) {}),
      ]) {
        addTearDown(subscription.close);
      }
      await container.read(spacesProvider.future);
      await container.read(spaceAccountsProvider.future);
      return container.read(accountLabelsProvider);
    }

    // Com uma conta só, repetir o nome dela em toda linha não distingue nada.
    test('uma conta não vira rótulo na lista', () async {
      expect(await labelsFor(['Conta corrente']), isEmpty);
    });

    test('nenhuma conta não vira rótulo', () async {
      expect(await labelsFor([]), isEmpty);
    });

    test('duas ou mais contas viram rótulo', () async {
      expect(await labelsFor(['Conta corrente', 'Cartão']), {
        'acc-1': 'Conta corrente',
        'acc-2': 'Cartão',
      });
    });
  });

  group('Linha da transação', () {
    Future<void> pumpRow(
      WidgetTester tester, {
      required Transaction transaction,
      Map<String, String> accountLabels = const {},
    }) => pumpScreen(
      tester,
      TransactionList(
        days: TransactionDay.groupByDay([transaction]),
        categoriesById: {'cat-1': testCategory()},
        accountLabels: accountLabels,
      ),
    );

    testWidgets('categoria e conta dividem a segunda linha', (tester) async {
      await pumpRow(
        tester,
        transaction: testTransaction(minor: 1000, accountId: 'acc-1'),
        accountLabels: const {'acc-1': 'Cartão'},
      );

      expect(find.text('Alimentação · Cartão'), findsOneWidget);
    });

    testWidgets('sem rótulo de conta, a linha fica como era', (tester) async {
      await pumpRow(
        tester,
        transaction: testTransaction(minor: 1000, accountId: 'acc-1'),
      );

      expect(find.text('Alimentação'), findsOneWidget);
    });

    // Sem descrição o título já é a categoria; a conta ainda assim precisa
    // caber, sem trazer de volta o "Alimentação / Alimentação".
    testWidgets('sem descrição, a segunda linha é só a conta', (tester) async {
      await pumpRow(
        tester,
        transaction: testTransaction(
          minor: 1000,
          accountId: 'acc-1',
          description: null,
        ),
        accountLabels: const {'acc-1': 'Cartão'},
      );

      expect(find.text('Alimentação'), findsOneWidget);
      expect(find.text('Cartão'), findsOneWidget);
    });
  });
}
