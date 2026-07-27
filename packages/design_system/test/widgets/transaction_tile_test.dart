import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  const expense = Money.fromMinor(-14280);
  const income = Money.fromMinor(540000);

  Widget tile({
    bool isIncome = false,
    bool isPending = false,
    bool isSelected = false,
    String? categoryId = 'alimentacao',
    String? meta = 'Alimentação · Conta corrente',
    VoidCallback? onTap,
  }) => TransactionTile(
    description: 'Mercado Pão de Açúcar',
    amount: isIncome ? income : expense,
    icon: Icons.shopping_basket_outlined,
    categoryId: categoryId,
    meta: meta,
    isIncome: isIncome,
    isPending: isPending,
    isSelected: isSelected,
    onTap: onTap,
  );

  group('TransactionTile', () {
    testWidgets('mostra descrição, metadado e valor', (tester) async {
      await pumpThemed(tester, tile());

      expect(find.text('Mercado Pão de Açúcar'), findsOneWidget);
      expect(find.text('Alimentação · Conta corrente'), findsOneWidget);
      expect(find.text('-142,80'), findsOneWidget);
    });

    testWidgets('despesa fica neutra e receita na marca', (tester) async {
      await pumpThemed(tester, tile());
      expect(textColor(tester, '-142,80'), AppTokens.light().moneyNeutral);

      await pumpThemed(tester, tile(isIncome: true));
      expect(textColor(tester, '+5.400,00'), AppTokens.light().moneyPositive);
    });

    testWidgets('respeita a altura de linha densa do sistema', (tester) async {
      await pumpThemed(tester, tile());

      final size = tester.getSize(find.byType(TransactionTile));
      expect(size.height, AppSizes.transactionRow);
    });

    testWidgets('sem categoria usa o swatch da marca', (tester) async {
      await pumpThemed(tester, tile(categoryId: null, isIncome: true));

      expect(find.byType(CategorySwatch), findsOneWidget);
    });

    testWidgets('dispara onTap', (tester) async {
      var taps = 0;
      await pumpThemed(tester, tile(onTap: () => taps++));

      await tester.tap(find.byType(TransactionTile));
      expect(taps, 1);
    });

    testWidgets('sem onTap não quebra ao tocar', (tester) async {
      await pumpThemed(tester, tile());

      await tester.tap(find.byType(TransactionTile));
      expect(tester.takeException(), isNull);
    });
  });

  group('TransactionTile — estado offline pendente', () {
    testWidgets('mostra o ícone de não sincronizado', (tester) async {
      await pumpThemed(tester, tile(isPending: true));

      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });

    testWidgets('não mostra o ícone quando já sincronizado', (tester) async {
      await pumpThemed(tester, tile());

      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    });

    testWidgets('acrescenta "aguardando envio" ao metadado', (tester) async {
      await pumpThemed(tester, tile(isPending: true));

      expect(
        find.text('Alimentação · Conta corrente · aguardando envio'),
        findsOneWidget,
      );
    });

    testWidgets('sem metadado, mostra só "aguardando envio"', (tester) async {
      await pumpThemed(tester, tile(isPending: true, meta: null));

      expect(find.text('aguardando envio'), findsOneWidget);
    });

    testWidgets('esmaece o valor', (tester) async {
      await pumpThemed(tester, tile(isPending: true));

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byType(MoneyText),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, lessThan(1));
    });
  });

  group('TransactionTile — seleção', () {
    testWidgets('selecionado recebe fundo na marca', (tester) async {
      await pumpThemed(tester, tile(isSelected: true));

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(TransactionTile),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.color, AppTokens.light().brandSubtle);
    });

    testWidgets('não selecionado não pinta fundo', (tester) async {
      await pumpThemed(tester, tile());

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(TransactionTile),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.color, isNull);
    });
  });

  group('CategorySwatch', () {
    testWidgets('mesma categoria sempre recebe a mesma cor', (tester) async {
      await pumpThemed(
        tester,
        const Column(
          children: [
            CategorySwatch(categoryId: 'lazer', icon: Icons.movie_outlined),
            CategorySwatch(categoryId: 'lazer', icon: Icons.movie_outlined),
          ],
        ),
      );

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .toList();
      final first = containers[0].decoration! as BoxDecoration;
      final second = containers[1].decoration! as BoxDecoration;

      expect(first.color, second.color);
    });

    testWidgets('a variante brand usa a cor da marca', (tester) async {
      await pumpThemed(
        tester,
        const CategorySwatch.brand(icon: Icons.attach_money),
      );

      final decoration =
          tester.widget<Container>(find.byType(Container)).decoration!
              as BoxDecoration;
      expect(decoration.color, AppTokens.light().brandSubtle);
    });
  });
}
