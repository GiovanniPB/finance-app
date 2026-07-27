import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  group('SavingsProgress', () {
    testWidgets('preenche sempre com a marca, nunca com âmbar ou vermelho', (
      tester,
    ) async {
      // A regra central do widget: encher uma meta é conquista, e barra de meta
      // não tem limiar de alerta. Se um dia alguém copiar a lógica de
      // `BudgetProgress` para cá, este teste reprova.
      for (final ratio in [0.0, 0.5, 0.85, 1.0, 1.4]) {
        await pumpThemed(
          tester,
          SavingsProgress(ratio: ratio),
        );

        final context = tester.element(find.byType(SavingsProgress));
        final tokens = Theme.of(context).extension<AppTokens>()!;
        final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );

        expect(
          indicator.valueColor?.value,
          Theme.of(context).colorScheme.primary,
          reason: 'razão $ratio deveria usar a marca',
        );
        expect(indicator.valueColor?.value, isNot(tokens.moneyOver));
        expect(indicator.valueColor?.value, isNot(tokens.attention));
      }
    });

    testWidgets('satura a barra quando passa do alvo', (tester) async {
      await pumpThemed(tester, const SavingsProgress(ratio: 1.8));

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

      expect(indicator.value, 1.0);
    });

    testWidgets('o trilho é mais alto que o do orçamento', (tester) async {
      // Não é decoração: na tela de Poupança o progresso é o conteúdo; na
      // home a barra de orçamento é informação secundária.
      await pumpThemed(tester, const SavingsProgress(ratio: 0.4));

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

      expect(indicator.minHeight, SavingsProgress.trackHeight);
      expect(SavingsProgress.trackHeight, greaterThan(5));
    });

    testWidgets('sem prazo, nenhuma marca de ritmo é desenhada', (
      tester,
    ) async {
      await pumpThemed(tester, const SavingsProgress(ratio: 0.4));

      expect(find.byType(Positioned), findsNothing);
    });

    testWidgets('com prazo, a marca aparece na fração do tempo', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const SizedBox(
          width: 200,
          child: SavingsProgress(ratio: 0.4, paceRatio: 0.5),
        ),
      );

      final tick = find.descendant(
        of: find.byType(SavingsProgress),
        matching: find.byType(DecoratedBox),
      );
      expect(tick, findsOneWidget);

      final rect = tester.getRect(tick);
      final track = tester.getRect(find.byType(LinearProgressIndicator));
      expect(rect.left - track.left, closeTo(track.width * 0.5, 2));
    });

    testWidgets('a marca não é cortada pela caixa', (tester) async {
      // O tick extrapola o trilho de propósito; se a caixa não couber o
      // excesso, ele aparece cortado e lê como defeito de renderização.
      await pumpThemed(
        tester,
        const SizedBox(
          width: 200,
          child: SavingsProgress(ratio: 0.4, paceRatio: 0.5),
        ),
      );

      final box = tester.getRect(find.byType(SavingsProgress));
      final tick = tester.getRect(
        find.descendant(
          of: find.byType(SavingsProgress),
          matching: find.byType(DecoratedBox),
        ),
      );

      expect(tick.top, greaterThanOrEqualTo(box.top));
      expect(tick.bottom, lessThanOrEqualTo(box.bottom));
      expect(tick.height, greaterThan(SavingsProgress.trackHeight));
    });

    testWidgets('anuncia o percentual para leitor de tela', (tester) async {
      await pumpThemed(
        tester,
        const SavingsProgress(ratio: 0.41, semanticLabel: 'Viagem ao Chile'),
      );

      expect(
        tester.getSemantics(find.byType(SavingsProgress)),
        matchesSemantics(label: 'Viagem ao Chile', value: '41%'),
      );
    });
  });

  group('CompletionSeal', () {
    testWidgets('usa a marca, e não a cor de erro', (tester) async {
      await pumpThemed(tester, const CompletionSeal());

      final context = tester.element(find.byType(CompletionSeal));
      final tokens = Theme.of(context).extension<AppTokens>()!;
      final icon = tester.widget<Icon>(find.byType(Icon));

      expect(icon.color, tokens.brandText);
      expect(icon.color, isNot(tokens.moneyOver));
      expect(find.text('CONCLUÍDA'), findsOneWidget);
    });

    testWidgets('o texto acompanha o ícone — cor não é o único sinal', (
      tester,
    ) async {
      await pumpThemed(tester, const CompletionSeal());

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('renderiza no tema escuro', (tester) async {
      await pumpThemed(tester, const CompletionSeal(), dark: true);

      expect(tester.takeException(), isNull);
    });
  });

  group('ScrollEdgeFade', () {
    testWidgets('não intercepta toque — não rouba gesto de rolagem', (
      tester,
    ) async {
      await pumpThemed(tester, const ScrollEdgeFade());

      // `descendant` porque o `MaterialApp` também tem os seus.
      expect(
        find.descendant(
          of: find.byType(ScrollEdgeFade),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });

    testWidgets('vai de transparente ao fundo da tela', (tester) async {
      await pumpThemed(tester, const ScrollEdgeFade());

      final context = tester.element(find.byType(ScrollEdgeFade));
      final background = Theme.of(context).scaffoldBackgroundColor;
      final decorated = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(ScrollEdgeFade),
          matching: find.byType(DecoratedBox),
        ),
      );
      final gradient =
          (decorated.decoration as BoxDecoration).gradient! as LinearGradient;

      // Alfa zero da PRÓPRIA cor, e não `Colors.transparent`: transparente é
      // preto com alfa zero, e interpolar por preto suja o meio do gradiente.
      expect(gradient.colors.first.a, 0);
      expect(gradient.colors.first.r, background.r);
      expect(gradient.colors.last, background);
    });
  });
}
