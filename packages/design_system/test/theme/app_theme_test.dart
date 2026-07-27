import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('light usa Material 3 e brilho claro', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('dark usa Material 3 e brilho escuro', () {
      final theme = AppTheme.dark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('mantém a semente histórica como âncora da rampa', () {
      expect(AppTheme.seedColor, const Color(0xFF1E6F5C));
      expect(AppTheme.seedColor, AppPalette.teal600);
    });

    test('a paleta é definida à mão, não derivada da semente', () {
      // fromSeed produziria a estética Material padrão. Se o primary deixar de
      // ser o teal escolhido, a paleta voltou a ser derivada.
      expect(AppTheme.light().colorScheme.primary, AppPalette.teal600);
      // No escuro a marca sobe: teal600 não sustenta texto em canvas escuro.
      expect(AppTheme.dark().colorScheme.primary, AppPalette.teal400);
    });

    test('registra os tokens como extensão em ambos os temas', () {
      expect(AppTheme.light().extension<AppTokens>(), isNotNull);
      expect(AppTheme.dark().extension<AppTokens>(), isNotNull);
    });

    test('o texto primário nunca é preto nem branco puro', () {
      expect(AppTheme.light().colorScheme.onSurface, isNot(Colors.black));
      expect(AppTheme.dark().colorScheme.onSurface, isNot(Colors.white));
    });

    test('divisores são hairlines de 1px', () {
      expect(AppTheme.light().dividerTheme.thickness, 1);
      expect(AppTheme.light().dividerTheme.color, AppTokens.light().hairline);
    });

    test('o foco do campo engrossa a borda para 2px na marca', () {
      final border =
          AppTheme.light().inputDecorationTheme.focusedBorder!
              as OutlineInputBorder;

      expect(border.borderSide.width, 2);
      expect(border.borderSide.color, AppPalette.teal600);
    });

    test('botão tem raio 12 e nunca pílula', () {
      final shape =
          AppTheme.light().filledButtonTheme.style!.shape!.resolve({})!
              as RoundedRectangleBorder;

      expect(shape.borderRadius, AppRadii.brLg);
    });

    test('card tem raio 16 e borda hairline', () {
      final shape = AppTheme.light().cardTheme.shape! as RoundedRectangleBorder;

      expect(shape.borderRadius, AppRadii.brXl);
      expect(shape.side.color, AppTokens.light().hairline);
    });

    test('a app bar não tem elevação', () {
      expect(AppTheme.light().appBarTheme.elevation, 0);
      expect(AppTheme.light().appBarTheme.scrolledUnderElevation, 0);
    });
  });

  group('AppTokensX — acesso por contexto', () {
    testWidgets('expõe tokens, cores e textos do tema ativo', (tester) async {
      late AppTokens tokens;
      late ColorScheme colors;
      late TextTheme texts;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              tokens = context.tokens;
              colors = context.colors;
              texts = context.texts;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(tokens.moneyPositive, AppPalette.teal600);
      expect(colors.primary, AppPalette.teal600);
      expect(texts.bodyMedium, isNotNull);
    });

    testWidgets('resolve os tokens do escuro quando o tema é escuro', (
      tester,
    ) async {
      late AppTokens tokens;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              tokens = context.tokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(tokens.cardShadow, isEmpty);
      expect(tokens.moneyPositive, AppPalette.teal300);
    });
  });

  group('AppTypography', () {
    test('todo estilo monetário tem figuras tabulares', () {
      const styles = [
        AppTypography.balance,
        AppTypography.moneyLarge,
        AppTypography.money,
        AppTypography.moneySmall,
      ];

      for (final style in styles) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'sem tabular, colunas de valores não alinham',
        );
        expect(style.fontFamily, AppTypography.monoFamily);
      }
    });

    test('o momento alto é o maior estilo do sistema', () {
      expect(AppTypography.balance.fontSize, 40);
      expect(
        AppTypography.balance.fontSize,
        greaterThan(AppTypography.moneyLarge.fontSize!),
      );
    });

    test('o TextTheme de prosa usa a família sans', () {
      final theme = AppTypography.textTheme(Colors.black, Colors.grey);

      expect(theme.bodyMedium!.fontFamily, AppTypography.sansFamily);
      expect(theme.displaySmall!.fontFamily, AppTypography.sansFamily);
    });

    test('rótulo auxiliar usa a cor muted informada', () {
      final theme = AppTypography.textTheme(Colors.black, Colors.grey);

      expect(theme.bodySmall!.color, Colors.grey);
      expect(theme.bodyMedium!.color, Colors.black);
    });
  });
}
