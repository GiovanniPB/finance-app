import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  group('AppButton', () {
    testWidgets('mostra o rótulo e dispara onPressed', (tester) async {
      var taps = 0;
      await pumpThemed(
        tester,
        AppButton(label: 'Salvar', onPressed: () => taps++),
      );

      expect(find.text('Salvar'), findsOneWidget);
      await tester.tap(find.text('Salvar'));
      expect(taps, 1);
    });

    testWidgets('onPressed nulo desabilita', (tester) async {
      await pumpThemed(
        tester,
        const AppButton(label: 'Salvar', onPressed: null),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, isFalse);
    });

    testWidgets('isLoading troca o rótulo por indicador e desabilita', (
      tester,
    ) async {
      var taps = 0;
      await pumpThemed(
        tester,
        AppButton(label: 'Salvar', onPressed: () => taps++, isLoading: true),
      );

      expect(find.text('Salvar'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      expect(taps, 0, reason: 'não deve disparar enquanto carrega');
    });

    testWidgets('ícone opcional aparece ao lado do rótulo', (tester) async {
      await pumpThemed(
        tester,
        AppButton(label: 'Registrar', onPressed: () {}, icon: Icons.add),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Registrar'), findsOneWidget);
    });

    testWidgets('expand=true ocupa a largura disponível', (tester) async {
      await pumpThemed(tester, AppButton(label: 'Salvar', onPressed: () {}));

      expect(find.byType(SizedBox), findsWidgets);
      final box = tester.getSize(find.byType(FilledButton));
      expect(box.width, greaterThan(400));
    });

    testWidgets('expand=false cabe no conteúdo', (tester) async {
      await pumpThemed(
        tester,
        Center(
          child: AppButton(label: 'Ok', onPressed: () {}, expand: false),
        ),
      );

      final box = tester.getSize(find.byType(FilledButton));
      expect(box.width, lessThan(400));
    });
  });

  group('AppButton — variantes', () {
    testWidgets('primary usa FilledButton', (tester) async {
      await pumpThemed(tester, AppButton(label: 'A', onPressed: () {}));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('secondary usa OutlinedButton', (tester) async {
      await pumpThemed(
        tester,
        AppButton(
          label: 'A',
          onPressed: () {},
          variant: AppButtonVariant.secondary,
        ),
      );
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('ghost usa TextButton', (tester) async {
      await pumpThemed(
        tester,
        AppButton(
          label: 'A',
          onPressed: () {},
          variant: AppButtonVariant.ghost,
        ),
      );
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('danger usa o vermelho reservado', (tester) async {
      await pumpThemed(
        tester,
        AppButton(
          label: 'Excluir',
          onPressed: () {},
          variant: AppButtonVariant.danger,
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final bg = button.style!.backgroundColor!.resolve({});
      expect(bg, AppPalette.red600);
    });

    testWidgets('cada variante renderiza seu indicador de carga', (
      tester,
    ) async {
      for (final variant in AppButtonVariant.values) {
        await pumpThemed(
          tester,
          AppButton(
            label: 'A',
            onPressed: () {},
            variant: variant,
            isLoading: true,
          ),
        );
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: 'variante $variant',
        );
      }
    });
  });
}
