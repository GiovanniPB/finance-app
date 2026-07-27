import 'package:design_system/design_system.dart';
import 'package:finance/features/accounts/domain/account.dart';
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
}
