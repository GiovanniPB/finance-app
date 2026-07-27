import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  group('AppEmptyState', () {
    testWidgets('mede pelo conteúdo, não pelo espaço disponível', (
      tester,
    ) async {
      // Num `Center` de tela inteira o card esticava até a borda e lia como
      // caixa de placeholder. Só parecia certo dentro de `ListView`, que
      // oferece altura infinita.
      await pumpThemed(
        tester,
        const Center(
          child: AppEmptyState(
            icon: Icons.savings_outlined,
            title: 'Nenhuma meta ainda',
            message: 'Uma frase curta.',
            actionLabel: 'Criar',
          ),
        ),
      );

      final card = tester.getRect(find.byType(AppEmptyState));
      final screen = tester.getRect(find.byType(Scaffold));

      expect(card.height, lessThan(screen.height / 2));
    });
  });

  group('BalanceHeader', () {
    testWidgets('usa o momento alto de 40px', (tester) async {
      await pumpThemed(
        tester,
        const BalanceHeader(
          label: 'Saldo de julho',
          amount: Money.fromMinor(418250),
        ),
      );

      expect(find.text('Saldo de julho'), findsOneWidget);
      expect(textStyleOf(tester, r'R$ 4.182,50').fontSize, 40);
    });

    testWidgets('inclui o símbolo da moeda no saldo', (tester) async {
      await pumpThemed(
        tester,
        const BalanceHeader(label: 'Saldo', amount: Money.fromMinor(418250)),
      );

      // Diferente da lista densa: aqui o valor é único e o R$ ajuda a ancorar.
      expect(find.text(r'R$ 4.182,50'), findsOneWidget);
    });

    testWidgets('delta e caption são opcionais', (tester) async {
      await pumpThemed(
        tester,
        const BalanceHeader(label: 'Saldo', amount: Money.zero()),
      );

      expect(find.text('+8,2%'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mostra delta e caption quando informados', (tester) async {
      await pumpThemed(
        tester,
        const BalanceHeader(
          label: 'Saldo',
          amount: Money.fromMinor(418250),
          delta: '+8,2%',
          caption: 'vs. junho · restam 4 dias',
        ),
      );

      expect(find.text('+8,2%'), findsOneWidget);
      expect(find.text('vs. junho · restam 4 dias'), findsOneWidget);
    });

    testWidgets('o delta comunica progresso relativo, na cor da marca', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const BalanceHeader(
          label: 'Saldo',
          amount: Money.fromMinor(418250),
          delta: '+8,2%',
        ),
      );

      expect(textColor(tester, '+8,2%'), AppTokens.light().moneyPositive);
    });
  });

  group('CategoryChip', () {
    testWidgets('dispara onSelected', (tester) async {
      var taps = 0;
      await pumpThemed(
        tester,
        CategoryChip(label: 'Alimentação', onSelected: () => taps++),
      );

      await tester.tap(find.text('Alimentação'));
      expect(taps, 1);
    });

    testWidgets('selecionado engrossa o peso além de mudar a cor', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        CategoryChip(
          label: 'Alimentação',
          onSelected: () {},
          isSelected: true,
        ),
      );

      final style = textStyleOf(tester, 'Alimentação');
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, AppTokens.light().brandText);
    });

    testWidgets('não selecionado usa peso e cor secundários', (tester) async {
      await pumpThemed(
        tester,
        CategoryChip(label: 'Alimentação', onSelected: () {}),
      );

      final style = textStyleOf(tester, 'Alimentação');
      expect(style.fontWeight, FontWeight.w500);
      expect(style.color, AppTokens.light().textSecondary);
    });

    testWidgets('onSelected nulo esmaece o chip', (tester) async {
      await pumpThemed(
        tester,
        const CategoryChip(label: 'Indisponível', onSelected: null),
      );

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, lessThan(1));
    });

    testWidgets('ícone opcional acompanha o rótulo', (tester) async {
      await pumpThemed(
        tester,
        CategoryChip(
          label: 'Transporte',
          onSelected: () {},
          icon: Icons.directions_bus_outlined,
        ),
      );

      expect(find.byIcon(Icons.directions_bus_outlined), findsOneWidget);
    });
  });

  group('AppSegmentedControl', () {
    testWidgets('mostra todos os segmentos', (tester) async {
      await pumpThemed(
        tester,
        AppSegmentedControl(
          segments: const ['Despesa', 'Receita'],
          selectedIndex: 0,
          onChanged: (_) {},
        ),
      );

      expect(find.text('Despesa'), findsOneWidget);
      expect(find.text('Receita'), findsOneWidget);
    });

    testWidgets('notifica o índice tocado', (tester) async {
      var selected = -1;
      await pumpThemed(
        tester,
        AppSegmentedControl(
          segments: const ['Despesa', 'Receita'],
          selectedIndex: 0,
          onChanged: (i) => selected = i,
        ),
      );

      await tester.tap(find.text('Receita'));
      expect(selected, 1);
    });

    testWidgets('o segmento ativo sobe de superfície', (tester) async {
      await pumpThemed(
        tester,
        AppSegmentedControl(
          segments: const ['Despesa', 'Receita'],
          selectedIndex: 0,
          onChanged: (_) {},
        ),
      );

      // Ativo destaca por superfície, não por cor de acento.
      expect(
        textStyleOf(tester, 'Despesa').color,
        AppTheme.light().colorScheme.onSurface,
      );
      expect(
        textStyleOf(tester, 'Receita').color,
        AppTokens.light().textMuted,
      );
    });

    testWidgets('suporta mais de dois segmentos', (tester) async {
      await pumpThemed(
        tester,
        AppSegmentedControl(
          segments: const ['Dia', 'Semana', 'Mês'],
          selectedIndex: 2,
          onChanged: (_) {},
        ),
      );

      expect(find.text('Mês'), findsOneWidget);
    });
  });

  group('AppEmptyState', () {
    testWidgets('nomeia a próxima ação', (tester) async {
      var taps = 0;
      await pumpThemed(
        tester,
        AppEmptyState(
          icon: Icons.add,
          title: 'Nenhum gasto em julho',
          message: 'Registre o primeiro em menos de 30 segundos.',
          actionLabel: 'Registrar gasto',
          onAction: () => taps++,
        ),
      );

      expect(find.text('Nenhum gasto em julho'), findsOneWidget);
      expect(find.text('Registrar gasto'), findsOneWidget);

      await tester.tap(find.text('Registrar gasto'));
      expect(taps, 1);
    });

    testWidgets('sem ação, não renderiza botão', (tester) async {
      await pumpThemed(
        tester,
        const AppEmptyState(
          icon: Icons.inbox_outlined,
          title: 'Vazio',
          message: 'Nada por aqui.',
        ),
      );

      expect(find.byType(AppButton), findsNothing);
    });
  });

  group('AppBottomNav', () {
    const destinations = [
      AppNavDestination(icon: Icons.home_outlined, label: 'Início'),
      AppNavDestination(icon: Icons.workspaces_outline, label: 'Espaços'),
      AppNavDestination(icon: Icons.people_outline, label: 'Social'),
      AppNavDestination(icon: Icons.person_outline, label: 'Perfil'),
    ];

    testWidgets('renderiza os destinos e a ação central', (tester) async {
      await pumpThemed(
        tester,
        AppBottomNav(
          destinations: destinations,
          currentIndex: 0,
          onSelected: (_) {},
          onCentralAction: () {},
        ),
      );

      expect(find.text('Início'), findsOneWidget);
      expect(find.text('Perfil'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('a ação central é independente dos destinos', (tester) async {
      var central = 0;
      var selected = -1;
      await pumpThemed(
        tester,
        AppBottomNav(
          destinations: destinations,
          currentIndex: 0,
          onSelected: (i) => selected = i,
          onCentralAction: () => central++,
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      expect(central, 1);
      expect(selected, -1, reason: 'não é um destino, não muda a seleção');
    });

    testWidgets('notifica o destino tocado com o índice correto', (
      tester,
    ) async {
      var selected = -1;
      await pumpThemed(
        tester,
        AppBottomNav(
          destinations: destinations,
          currentIndex: 0,
          onSelected: (i) => selected = i,
          onCentralAction: () {},
        ),
      );

      // "Social" é o índice 2, mesmo aparecendo depois da ação central.
      await tester.tap(find.text('Social'));
      expect(selected, 2);
    });

    testWidgets('o destino ativo usa a cor da marca', (tester) async {
      await pumpThemed(
        tester,
        AppBottomNav(
          destinations: destinations,
          currentIndex: 1,
          onSelected: (_) {},
          onCentralAction: () {},
        ),
      );

      expect(textColor(tester, 'Espaços'), AppTokens.light().brandText);
      expect(textColor(tester, 'Início'), AppTokens.light().textMuted);
    });

    testWidgets('respeita a altura do sistema', (tester) async {
      await pumpThemed(
        tester,
        AppBottomNav(
          destinations: destinations,
          currentIndex: 0,
          onSelected: (_) {},
          onCentralAction: () {},
        ),
      );

      expect(
        tester.getSize(find.byType(AppBottomNav)).height,
        AppSizes.bottomNav,
      );
    });
  });

  group('AppTextField e MoneyField', () {
    testWidgets('AppTextField mostra rótulo, dica e erro', (tester) async {
      await pumpThemed(
        tester,
        const AppTextField(
          label: 'Descrição',
          hint: 'Ex.: mercado',
          errorText: 'Campo obrigatório',
        ),
      );

      expect(find.text('Descrição'), findsOneWidget);
      expect(find.text('Ex.: mercado'), findsOneWidget);
      expect(find.text('Campo obrigatório'), findsOneWidget);
    });

    testWidgets('AppTextField propaga onChanged', (tester) async {
      var value = '';
      await pumpThemed(tester, AppTextField(onChanged: (v) => value = v));

      await tester.enterText(find.byType(TextField), 'mercado');
      expect(value, 'mercado');
    });

    testWidgets('MoneyField alinha à direita em fonte mono tabular', (
      tester,
    ) async {
      await pumpThemed(tester, const MoneyField(label: 'Valor'));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textAlign, TextAlign.right);
      expect(field.style!.fontFamily, AppTypography.monoFamily);
      expect(
        field.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('MoneyField mantém o símbolo fora do texto editável', (
      tester,
    ) async {
      await pumpThemed(tester, const MoneyField());

      expect(find.text(r'R$'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '142,80');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text ?? '142,80', isNot(contains(r'R$')));
    });

    testWidgets('MoneyField usa teclado numérico com decimal', (tester) async {
      await pumpThemed(tester, const MoneyField());

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(
          decimal: true,
        ),
      );
    });
  });
}
