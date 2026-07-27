import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  group('AmountDisplay', () {
    testWidgets('mostra o valor e o símbolo como prefixo', (tester) async {
      await pumpThemed(tester, const AmountDisplay(label: '1.234,56'));

      expect(find.text('1.234,56'), findsOneWidget);
      expect(find.text(r'R$'), findsOneWidget);
    });

    testWidgets('o valor é 40px mono tabular, o símbolo não compete', (
      tester,
    ) async {
      await pumpThemed(tester, const AmountDisplay(label: '0,00'));

      final value = textStyleOf(tester, '0,00');
      final symbol = textStyleOf(tester, r'R$');

      expect(value.fontSize, 40);
      expect(value.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(symbol.fontSize, lessThan(value.fontSize!));
    });

    testWidgets('a chave do valor é estável para o teste ler', (tester) async {
      await pumpThemed(tester, const AmountDisplay(label: '9,99'));

      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '9,99',
      );
    });

    testWidgets('aceita outro símbolo de moeda', (tester) async {
      await pumpThemed(
        tester,
        const AmountDisplay(label: '10,00', symbol: r'US$'),
      );

      expect(find.text(r'US$'), findsOneWidget);
    });

    testWidgets('constrói nos dois temas sem overflow', (tester) async {
      for (final dark in [false, true]) {
        await pumpThemed(
          tester,
          const AmountDisplay(label: '99.999.999,99'),
          dark: dark,
        );

        expect(tester.takeException(), isNull);
      }
    });
  });

  group('AmountKeypad', () {
    testWidgets('tem os dez dígitos e o apagar', (tester) async {
      await pumpThemed(
        tester,
        AmountKeypad(onDigit: (_) {}, onBackspace: () {}),
      );

      for (var digit = 0; digit <= 9; digit++) {
        expect(find.text('$digit'), findsOneWidget);
      }
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    });

    testWidgets('devolve o dígito tocado', (tester) async {
      final pressed = <int>[];
      await pumpThemed(
        tester,
        AmountKeypad(onDigit: pressed.add, onBackspace: () {}),
      );

      await tester.tap(find.text('4'));
      await tester.tap(find.text('2'));
      await tester.tap(find.text('0'));

      expect(pressed, [4, 2, 0]);
    });

    testWidgets('dispara onBackspace', (tester) async {
      var backspaces = 0;
      await pumpThemed(
        tester,
        AmountKeypad(onDigit: (_) {}, onBackspace: () => backspaces++),
      );

      await tester.tap(find.byIcon(Icons.backspace_outlined));

      expect(backspaces, 1);
    });

    testWidgets('não tem tecla de vírgula — o decimal é implícito', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        AmountKeypad(onDigit: (_) {}, onBackspace: () {}),
      );

      expect(find.text(','), findsNothing);
      expect(find.text('.'), findsNothing);
    });

    testWidgets('o apagar tem rótulo semântico', (tester) async {
      await pumpThemed(
        tester,
        AmountKeypad(onDigit: (_) {}, onBackspace: () {}),
      );

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.backspace_outlined),
      );
      expect(icon.semanticLabel, 'Apagar');
    });

    testWidgets('mantém a grade 3×4 alinhada nos dois temas', (tester) async {
      for (final dark in [false, true]) {
        await pumpThemed(
          tester,
          AmountKeypad(onDigit: (_) {}, onBackspace: () {}),
          dark: dark,
        );

        // Quatro linhas de 46px mais o espaçamento inferior de cada uma.
        expect(tester.getSize(find.byType(AmountKeypad)).height, 4 * (46 + 8));
        expect(tester.takeException(), isNull);
      }
    });
  });
}
