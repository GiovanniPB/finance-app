import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Tema do app — ponto único de verdade para cor e tipografia.
///
/// A paleta é **definida à mão**, não derivada de `ColorScheme.fromSeed`.
/// Derivar de semente garante contraste acessível, mas produz a estética
/// Material padrão; identidade visual exige papéis escolhidos.
///
/// O tema escuro é **desenhado, não invertido** — ver [AppTokens.dark].
abstract final class AppTheme {
  /// Cor-semente histórica da identidade. Mantida como âncora da rampa teal.
  static const Color seedColor = AppPalette.teal600;

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppPalette.teal600,
      primaryContainer: AppPalette.teal50,
      onPrimaryContainer: AppPalette.teal800,
      secondary: AppPalette.teal500,
      onSecondary: AppPalette.white,
      surface: AppPalette.ink50,
      onSurface: AppPalette.ink900,
      surfaceContainerLowest: AppPalette.white,
      surfaceContainerLow: AppPalette.white,
      surfaceContainer: AppPalette.ink100,
      error: AppPalette.red600,
      errorContainer: AppPalette.red100,
      onErrorContainer: AppPalette.red700,
      outline: AppPalette.ink300,
      outlineVariant: AppPalette.ink200,
    );
    return _build(scheme, AppTokens.light());
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppPalette.teal400,
      onPrimary: Color(0xFF06120F),
      primaryContainer: Color(0x2443A68D),
      onPrimaryContainer: AppPalette.teal200,
      secondary: AppPalette.teal300,
      onSecondary: Color(0xFF06120F),
      surface: AppPalette.darkCanvas,
      onSurface: AppPalette.darkInk,
      surfaceContainerLowest: AppPalette.darkCanvas,
      surfaceContainerLow: AppPalette.darkCard,
      surfaceContainer: AppPalette.darkRaised,
      error: AppPalette.redDark,
      onError: Color(0xFF2A0A06),
      outline: Color(0x29FFFFFF),
      outlineVariant: Color(0x14FFFFFF),
    );
    return _build(scheme, AppTokens.dark());
  }

  static ThemeData _build(ColorScheme scheme, AppTokens tokens) {
    final textTheme = AppTypography.textTheme(
      scheme.onSurface,
      tokens.textMuted,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      fontFamily: AppTypography.sansFamily,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      extensions: [tokens],

      // Divisores são o mecanismo primário de separação: 1px, hairline.
      dividerTheme: DividerThemeData(
        color: tokens.hairline,
        thickness: 1,
        space: 1,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.brXl,
          side: BorderSide(color: tokens.hairline),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Size(0, h) e NÃO Size.fromHeight(h): fromHeight põe largura
          // infinita no mínimo, o que forçaria todo botão a ocupar a linha
          // inteira e tornaria `AppButton.expand: false` inócuo.
          minimumSize: const Size(0, AppSizes.buttonHeight),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.brLg),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.buttonHeight),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.brLg),
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: tokens.hairlineStrong),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSizes.touchTarget),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.brLg),
          textStyle: textTheme.labelLarge,
          foregroundColor: tokens.brandText,
        ),
      ),

      // Foco engrossa a borda para 2px na marca — sem glow, sem anel.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.brMd,
          borderSide: BorderSide(color: tokens.hairlineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.brMd,
          borderSide: BorderSide(color: tokens.hairlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.brMd,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.brMd,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.brMd,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.brMd,
          borderSide: BorderSide(color: tokens.hairline),
        ),
        labelStyle: textTheme.labelMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brSheet),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: tokens.brandSubtle,
        side: BorderSide(color: tokens.hairline),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brFull),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      listTileTheme: ListTileThemeData(
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.labelMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brMd),
        behavior: SnackBarBehavior.floating,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: tokens.surfaceSunken,
        linearMinHeight: 5,
      ),
    );
  }
}

/// Acesso ergonômico aos tokens que o Material não modela.
///
/// O `!` é deliberado: extensão ausente significa tema mal configurado — erro
/// de programação, em que estourar é o comportamento correto.
extension AppTokensX on BuildContext {
  /// Tokens do tema ativo (cores de dinheiro, categoria, hairline, sombra).
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;

  /// Atalho para o `ColorScheme` ativo.
  ColorScheme get colors => Theme.of(this).colorScheme;

  /// Atalho para o `TextTheme` ativo.
  TextTheme get texts => Theme.of(this).textTheme;
}
