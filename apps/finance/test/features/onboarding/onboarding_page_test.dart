import 'package:design_system/design_system.dart';
import 'package:finance/features/onboarding/presentation/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  late FakeOnboardingPreferences prefs;

  setUp(() => prefs = FakeOnboardingPreferences());

  Future<void> pumpOnboarding(WidgetTester tester, {bool dark = false}) =>
      pumpScreen(
        tester,
        const OnboardingPage(),
        wrapInScaffold: false,
        dark: dark,
        onboardingPreferences: prefs,
        onboardingSeenAtBoot: false,
      );

  Future<void> advance(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('onboarding_advance')));
    await tester.pumpAndSettle();
  }

  /// Fecha a folha de registro rápido pelo navigator, como o gesto de arrastar
  /// faria — `tapAt` no scrim depende de onde a folha termina.
  Future<void> closeSheet(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  group('OnboardingPage', () {
    testWidgets('abre no pilar 1, com o valor alto e o fragmento real', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      expect(find.textContaining('Pilar 1'), findsOneWidget);
      expect(find.text('disponível agora'), findsOneWidget);
      expect(find.text('1.240,50'), findsOneWidget);
      expect(
        find.text('Anote em três toques. Veja o mês inteiro.'),
        findsOneWidget,
      );
      // O fragmento é a linha de verdade do design system, não uma ilustração.
      expect(find.byType(TransactionTile), findsNWidgets(3));
    });

    testWidgets('a regra de dinheiro é demonstrada no primeiro pilar', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      // Receita ganha `+` explícito; despesa sai sem sinal de cor nenhum.
      expect(find.text('+5.400,00'), findsOneWidget);
      expect(find.text('-98,40'), findsOneWidget);
    });

    testWidgets('progresso em barras, uma por pilar', (tester) async {
      await pumpOnboarding(tester);

      expect(find.byType(AnimatedContainer), findsNWidgets(3));
    });

    testWidgets('avança pelos pilares e o botão muda de rótulo no fim', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      expect(find.text('Avançar'), findsOneWidget);

      await advance(tester);
      expect(find.textContaining('Pilar 2'), findsOneWidget);
      expect(find.text('Avançar'), findsOneWidget);

      await advance(tester);
      expect(find.textContaining('Pilar 3'), findsOneWidget);
      expect(find.text('Começar'), findsOneWidget);
    });

    testWidgets('o pilar que ainda não existe diz que não existe', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await advance(tester);

      expect(find.text('em breve'), findsOneWidget);
      expect(find.text('Chega numa fase futura'), findsOneWidget);
      // Prometer sem ressalva seria mentir: pilar 2 é da fase 1.
      expect(find.text('disponível agora'), findsNothing);
    });

    testWidgets('Pular grava a preferência uma vez', (tester) async {
      await pumpOnboarding(tester);

      await tester.tap(find.byKey(const Key('onboarding_skip')));
      await tester.pumpAndSettle();

      expect(prefs.marked, 1);
    });

    testWidgets('Começar abre o registro rápido, não uma home vazia', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await advance(tester);
      await advance(tester);

      await advance(tester);

      expect(find.byKey(AmountDisplay.valueKey), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget);
      // Uma linha de orientação, porque um campo de valor em branco levanta a
      // pergunta "qual gasto?".
      expect(find.text('Comece pelo gasto mais recente.'), findsOneWidget);
    });

    testWidgets('a preferência só é gravada quando a folha fecha', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await advance(tester);
      await advance(tester);
      await advance(tester);

      // Gravar antes tiraria esta tela da árvore no meio da transição — o guard
      // redirecionaria — e a folha morreria com ela.
      expect(prefs.marked, 0);

      await closeSheet(tester);

      expect(prefs.marked, 1);
    });

    testWidgets('o fundo da entrega mostra o saldo em repouso', (tester) async {
      await pumpOnboarding(tester);
      await advance(tester);
      await advance(tester);
      await advance(tester);
      await closeSheet(tester);

      // Nada aconteceu ainda, e a tela diz isso em vez de inventar um número.
      expect(find.text(r'R$ 0,00'), findsOneWidget);
      expect(find.text('Espaço ativo'), findsOneWidget);
    });

    testWidgets('funciona no tema escuro sem overflow', (tester) async {
      await pumpOnboarding(tester, dark: true);

      expect(tester.takeException(), isNull);
    });

    testWidgets('cada pilar mostra exatamente um valor alto', (tester) async {
      await pumpOnboarding(tester);

      // A regra do sistema: um único elemento em 40px por tela.
      for (final label in ['1.240,50', '1.400,00', '61,30']) {
        expect(find.text(label), findsOneWidget);
        await advance(tester);
      }
    });
  });
}
