import 'package:design_system/design_system.dart';
import 'package:finance/features/accounts/domain/account.dart';
import 'package:finance/features/accounts/presentation/account_form_sheet.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Botão que abre a folha, para o teste exercitar o fluxo real (`show`) em vez
/// de montar o widget da folha solto.
class _Opener extends StatelessWidget {
  const _Opener({this.editing});

  final Account? editing;

  @override
  Widget build(BuildContext context) => Center(
    child: ElevatedButton(
      onPressed: () => AccountFormSheet.show(context, editing: editing),
      child: const Text('abrir'),
    ),
  );
}

Space householdSpace() => Space(
  id: 'space-2',
  type: SpaceType.household,
  name: 'Casa',
  ownerId: 'user-1',
  privacy: SpacePrivacy.fullTransparency,
  status: SpaceStatus.active,
  settlementCurrency: 'BRL',
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

void main() {
  // A superfície padrão do teste é 800×600 — paisagem, mais larga que alta.
  // A folha é desenhada para telefone em pé, e num retângulo deitado ela cabe
  // toda de uma vez, escondendo justamente o que o rodapé fixo resolve.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
          ..devicePixelRatio = 3.0
          ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(() {
      view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
  });

  Future<FakeAccountsRepository> openSheet(
    WidgetTester tester, {
    Account? editing,
    List<Space>? spaces,
  }) async {
    final repository = FakeAccountsRepository();
    await pumpScreen(
      tester,
      _Opener(editing: editing),
      spaces: spaces,
      accountsRepository: repository,
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return repository;
  }

  /// Digita um valor no teclado próprio da folha.
  Future<void> typeAmount(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tapVisible(
        tester,
        find.descendant(
          of: find.byType(AmountKeypad),
          matching: find.widgetWithText(InkWell, digit),
        ),
      );
    }
  }

  group('AccountFormSheet — criar', () {
    testWidgets('cria com nome, tipo e saldo', (tester) async {
      final repository = await openSheet(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'Conta do salário',
      );
      await tester.tap(find.byKey(const Key('account_type_savings')));
      await tester.pump();
      await typeAmount(tester, '15000');

      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();

      expect(repository.created, hasLength(1));
      expect(repository.created.single.name, 'Conta do salário');
      expect(repository.created.single.type, AccountType.savings);
      expect(repository.created.single.currentBalance.amountMinor, 15000);
    });

    testWidgets('Criar conta fica desabilitado sem nome', (tester) async {
      await openSheet(tester);

      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Criar conta'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a legenda do saldo muda com o tipo', (tester) async {
      await openSheet(tester);

      expect(find.text('Saldo de hoje'), findsOneWidget);

      await tester.tap(find.byKey(const Key('account_type_credit_card')));
      await tester.pump();

      // Em cartão o número é o que se deve, não o que se tem — e o app diz
      // isso em vez de inventar um sinal que o usuário não digitou.
      expect(find.text('Fatura atual — o quanto você deve'), findsOneWidget);
    });

    testWidgets('sem household, o campo de vínculo não aparece', (
      tester,
    ) async {
      await openSheet(tester);

      expect(find.text('Visível para'), findsNothing);
    });

    testWidgets('com household, dá para vincular a conta', (tester) async {
      // Tela alta de propósito: com o campo de vínculo a folha fica mais
      // comprida que a rolagem do teste consegue percorrer de forma estável,
      // e o que se quer verificar aqui é o vínculo, não a rolagem.
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);

      final repository = await openSheet(
        tester,
        spaces: [personalSpace(), householdSpace()],
      );

      expect(find.text('Visível para'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Conjunta');
      await tapVisible(tester, find.byKey(const Key('link_space_space-2')));
      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();

      expect(repository.created.single.linkedSpaceId, 'space-2');
    });
  });

  group('AccountFormSheet — editar', () {
    testWidgets('abre preenchido com a conta', (tester) async {
      await openSheet(
        tester,
        editing: testAccount(
          name: 'Conta antiga',
          institution: 'Itaú',
          balanceMinor: 123400,
        ),
      );

      expect(find.text('Editar conta'), findsOneWidget);
      expect(find.text('Conta antiga'), findsOneWidget);
      expect(find.text('Itaú'), findsOneWidget);
      expect(find.text('1.234,00'), findsOneWidget);
    });

    testWidgets('salva a alteração preservando id e dono', (tester) async {
      final repository = await openSheet(
        tester,
        editing: testAccount(name: 'Conta antiga'),
      );

      await tester.enterText(find.byType(TextField).first, 'Conta nova');
      await tapVisible(tester, find.byKey(const Key('account_savings_target')));
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(repository.updated, hasLength(1));
      expect(repository.updated.single.id, 'acc-1');
      expect(repository.updated.single.ownerId, 'user-1');
      expect(repository.updated.single.name, 'Conta nova');
      expect(repository.updated.single.isSavingsTarget, isTrue);
    });

    testWidgets('excluir pede confirmação antes de remover', (tester) async {
      final repository = await openSheet(tester, editing: testAccount());

      await tester.tap(find.byKey(const Key('account_delete')));
      await tester.pumpAndSettle();

      expect(find.text('Excluir conta?'), findsOneWidget);
      // O diálogo diz o que acontece com os lançamentos: eles ficam.
      expect(find.textContaining('continuam existindo'), findsOneWidget);
      expect(repository.deleted, isEmpty);

      await tester.tap(find.byKey(const Key('confirm_delete_account')));
      await tester.pumpAndSettle();

      expect(repository.deleted, ['acc-1']);
    });

    testWidgets('cancelar a confirmação não remove nada', (tester) async {
      final repository = await openSheet(tester, editing: testAccount());

      await tester.tap(find.byKey(const Key('account_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repository.deleted, isEmpty);
    });

    testWidgets('conta nova não oferece excluir', (tester) async {
      await openSheet(tester);

      expect(find.byKey(const Key('account_delete')), findsNothing);
    });
  });

  group('AccountFormSheet — conta de Open Finance', () {
    Account imported({int balanceMinor = 419788}) => testAccount(
      id: 'acc-of',
      name: 'ultraviolet-black',
      type: AccountType.creditCard,
      balanceMinor: balanceMinor,
      connectionId: 'conn-1',
    );

    testWidgets('o que é da Pluggy aparece como fato, não como campo', (
      tester,
    ) async {
      await openSheet(tester, editing: imported());

      expect(
        find.byKey(const Key('account_provider_owned')),
        findsOneWidget,
      );
      expect(find.text('Cartão de crédito'), findsOneWidget);
      // Sem seletor de tipo e sem teclado: são as duas coisas que a
      // sincronização reescreveria.
      expect(
        find.byKey(const Key('account_type_credit_card')),
        findsNothing,
      );
      expect(find.byType(AmountKeypad), findsNothing);
    });

    testWidgets('o que é do usuário continua editável', (tester) async {
      await openSheet(tester, editing: imported());

      // Nome e instituição: a ingestão só escreve `name` no INSERT e nunca
      // toca em `institution`.
      expect(find.text('Nome'), findsOneWidget);
      expect(find.text('Instituição'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget);
    });

    testWidgets(
      'excluir não existe: a sincronização recriaria a conta e reimportaria o '
      'extrato inteiro',
      (tester) async {
        await openSheet(tester, editing: imported());

        expect(find.byKey(const Key('account_delete')), findsNothing);
      },
    );

    testWidgets('conta digitada segue com tipo, teclado e excluir', (
      tester,
    ) async {
      await openSheet(tester, editing: testAccount());

      expect(find.byKey(const Key('account_provider_owned')), findsNothing);
      expect(find.byType(AmountKeypad), findsOneWidget);
      expect(find.byKey(const Key('account_delete')), findsOneWidget);
    });
  });

  group('AccountFormSheet — nos dois temas', () {
    for (final dark in [false, true]) {
      testWidgets('sem overflow no tema ${dark ? 'escuro' : 'claro'}', (
        tester,
      ) async {
        final repository = FakeAccountsRepository();
        await pumpScreen(
          tester,
          const _Opener(),
          accountsRepository: repository,
          dark: dark,
        );
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Nova conta'), findsOneWidget);
      });
    }
  });
}
