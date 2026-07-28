import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:finance/features/accounts/domain/account.dart';
import 'package:finance/features/categories/domain/category.dart';
import 'package:finance/features/profile/presentation/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  group('ProfilePage', () {
    testWidgets('sem conta, convida a cadastrar em vez de mostrar zero', (
      tester,
    ) async {
      await pumpScreen(tester, const ProfilePage());

      expect(find.text('Nenhuma conta cadastrada'), findsOneWidget);
      expect(find.text('Nova conta'), findsOneWidget);
      // Total sem conta nenhuma seria uma mentira arredondada.
      expect(find.byKey(const Key('accounts_net_balance')), findsNothing);
    });

    testWidgets('lista as contas com tipo e instituição', (tester) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        accounts: [
          testAccount(institution: 'Nubank'),
          testAccount(
            id: 'acc-2',
            name: 'Reserva',
            type: AccountType.savings,
            isSavingsTarget: true,
          ),
        ],
      );

      expect(find.text('Conta corrente'), findsOneWidget);
      expect(find.textContaining('Nubank'), findsOneWidget);
      expect(find.text('Reserva'), findsOneWidget);
      expect(find.textContaining('Poupança'), findsOneWidget);
    });

    testWidgets('soma as contas descontando a fatura do cartão', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        accounts: [
          testAccount(),
          testAccount(
            id: 'acc-2',
            name: 'Cartão',
            type: AccountType.creditCard,
            balanceMinor: 50000,
          ),
        ],
      );

      // 2500,00 − 500,00 (a fatura é dívida, ainda que digitada positiva).
      expect(find.text(r'R$ 2.000,00'), findsOneWidget);
    });

    // Guarda da regra central do design system: cor só para receita e para
    // orçamento estourado. Dever no cartão é estado ordinário — pintar de
    // vermelho seria o "vermelho-para-despesa lê como erro" que a regra evita.
    testWidgets('fatura de cartão não ganha cor de alarme', (tester) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        accounts: [
          testAccount(
            name: 'Cartão',
            type: AccountType.creditCard,
            balanceMinor: 50000,
          ),
        ],
      );

      final amounts = tester.widgetList<MoneyText>(find.byType(MoneyText));
      expect(amounts, isNotEmpty);
      for (final amount in amounts) {
        expect(amount.tone, MoneyTone.neutral);
      }
    });

    // Saldo é snapshot: registrar gasto não o move. Sem a data, o número
    // envelhece calado e ninguém percebe.
    testWidgets('o saldo diz de quando é, em minúscula', (tester) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        accounts: [testAccount(balanceAsOf: DateTime.utc(2026, 3, 5, 12))],
      );

      expect(find.text('de 5 de março'), findsOneWidget);
    });

    testWidgets('não some com a promessa das fases seguintes', (tester) async {
      await pumpScreen(tester, const ProfilePage());

      expect(find.text('Assinatura e preferências'), findsOneWidget);
    });
  });

  group('seção de categorias', () {
    /// Uma categoria criada pelo usuário — `testCategory` faz de sistema.
    Category minha({String id = 'cat-user', String name = 'Academia'}) =>
        Category(
          id: id,
          name: name,
          iconKey: 'fitness',
          isSystem: false,
          createdAt: testNow,
          updatedAt: testNow,
          spaceId: 'space-1',
        );

    testWidgets('lista só as criadas pelo usuário', (tester) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        categories: [testCategory(), minha()],
      );

      expect(find.text('Suas categorias'), findsOneWidget);
      expect(find.byKey(const Key('category_cat-user')), findsOneWidget);
      // A de sistema não entra: não é editável, e uma linha que não responde ao
      // toque numa seção de gerenciamento é ruído.
      expect(find.byKey(const Key('category_cat-1')), findsNothing);
    });

    testWidgets('sem categoria própria, explica em vez de mostrar vazio', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        categories: [testCategory()],
      );

      expect(find.byKey(const Key('no_user_categories')), findsOneWidget);
      // A ação continua oferecida.
      expect(find.byKey(const Key('new_category')), findsOneWidget);
    });

    testWidgets('tocar a linha abre a edição preenchida', (tester) async {
      await pumpScreen(tester, const ProfilePage(), categories: [minha()]);

      await tester.tap(find.byKey(const Key('category_cat-user')));
      await tester.pumpAndSettle();

      expect(find.text('Editar categoria'), findsOneWidget);
      // O campo abre preenchido — sem isso, salvar apagaria o nome. Asserção no
      // `TextField`, e não contagem de ocorrências: o nome aparece três vezes
      // (a linha do Perfil atrás da folha, a prévia e o campo).
      expect(find.widgetWithText(TextField, 'Academia'), findsOneWidget);
      expect(find.byKey(const Key('category_delete')), findsOneWidget);
    });

    testWidgets('salvar a edição persiste o que mudou', (tester) async {
      final categories = FakeCategoriesRepository([minha()]);
      await pumpScreen(
        tester,
        const ProfilePage(),
        categoriesRepository: categories,
      );

      await tester.tap(find.byKey(const Key('category_cat-user')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Musculação');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('category_form_save')));

      expect(categories.updated.single.name, 'Musculação');
      expect(categories.updated.single.id, 'cat-user');
    });

    testWidgets('excluir pede confirmação e diz que só sai a sem lançamento', (
      tester,
    ) async {
      final categories = FakeCategoriesRepository([minha()]);
      await pumpScreen(
        tester,
        const ProfilePage(),
        categoriesRepository: categories,
      );

      await tester.tap(find.byKey(const Key('category_cat-user')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('category_delete')));

      expect(find.text('Excluir esta categoria?'), findsOneWidget);
      expect(find.textContaining('nenhum lançamento usa'), findsOneWidget);
      expect(categories.deleted, isEmpty);

      await tapVisible(
        tester,
        find.byKey(const Key('confirm_delete_category')),
      );

      expect(categories.deleted, ['cat-user']);
    });

    testWidgets('a recusa por uso aparece na folha, sem fechá-la', (
      tester,
    ) async {
      // A mensagem vem do repository, com a contagem — a folha não a duplica.
      final categories = FakeCategoriesRepository([minha()])
        ..writeFailure = const ValidationFailure(
          '3 lançamentos usam esta categoria. Mude a categoria deles antes de '
          'remover.',
        );
      await pumpScreen(
        tester,
        const ProfilePage(),
        categoriesRepository: categories,
      );

      await tester.tap(find.byKey(const Key('category_cat-user')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('category_delete')));
      await tapVisible(
        tester,
        find.byKey(const Key('confirm_delete_category')),
      );

      expect(find.byKey(const Key('category_form_error')), findsOneWidget);
      expect(find.textContaining('3 lançamentos'), findsOneWidget);
      // A folha fica aberta: o usuário precisa da mensagem para agir.
      expect(find.text('Editar categoria'), findsOneWidget);
    });
  });
}
