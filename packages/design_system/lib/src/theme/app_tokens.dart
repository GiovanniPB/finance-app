import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Par de cores de uma categoria: fundo do swatch + cor do ícone.
@immutable
class CategoryColors {
  const CategoryColors({required this.fill, required this.ink});

  /// Interpola entre [a] e [b] — usado pelo `lerp` de [AppTokens].
  factory CategoryColors.lerp(CategoryColors a, CategoryColors b, double t) =>
      CategoryColors(
        fill: Color.lerp(a.fill, b.fill, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
      );

  final Color fill;
  final Color ink;

  @override
  bool operator ==(Object other) =>
      other is CategoryColors && other.fill == fill && other.ink == ink;

  @override
  int get hashCode => Object.hash(fill, ink);
}

/// Tokens que o Material não modela — e que **variam por tema**.
///
/// Espaçamento, raio e movimento são invariantes e vivem em classes `const`
/// (`AppSpacing`, `AppRadii`, `AppMotion`): interpolar números que nunca mudam
/// só adicionaria ruído. Aqui ficam apenas os tokens com valor diferente entre
/// claro e escuro, que é o que justifica o [ThemeExtension] — ganham `lerp`
/// automático na transição de tema.
///
/// Acesso: `context.tokens` (ver extensão em `app_theme.dart`).
///
/// ## A regra central: despesa é o estado neutro
///
/// Um app de despesas mostra despesa em ~90% das linhas. Colorir isso é ruído,
/// e vermelho-para-despesa lê como *erro* na ação mais ordinária do produto.
/// Portanto:
///
/// - despesa → [moneyNeutral], sem cor nenhuma;
/// - receita → [moneyPositive] + prefixo `+` explícito;
/// - orçamento ≥ 80% → [moneyWarning] + rótulo de percentual;
/// - orçamento > 100% → [moneyOver] + rótulo de percentual.
///
/// Cor **nunca** é o único sinal: sinal aritmético, peso e rótulo textual
/// carregam o significado junto. No caso comum não há nada codificado por cor,
/// o que torna o sistema robusto para deficiência de visão de cores.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.moneyNeutral,
    required this.moneyPositive,
    required this.moneyWarning,
    required this.moneyOver,
    required this.attention,
    required this.attentionSubtle,
    required this.brandSubtle,
    required this.brandBorder,
    required this.brandText,
    required this.hairline,
    required this.hairlineStrong,
    required this.surfaceSunken,
    required this.textSecondary,
    required this.textMuted,
    required this.cardShadow,
    required this.microShadow,
    required this.categoryPalette,
  });

  /// Tokens do tema claro.
  factory AppTokens.light() => const AppTokens(
    moneyNeutral: AppPalette.ink900,
    moneyPositive: AppPalette.teal600,
    moneyWarning: AppPalette.amber600,
    moneyOver: AppPalette.red600,
    attention: AppPalette.amber600,
    attentionSubtle: AppPalette.amber100,
    brandSubtle: AppPalette.teal50,
    brandBorder: AppPalette.teal200,
    brandText: AppPalette.teal700,
    hairline: AppPalette.ink200,
    hairlineStrong: AppPalette.ink300,
    surfaceSunken: AppPalette.ink100,
    textSecondary: AppPalette.ink700,
    textMuted: AppPalette.ink600,
    cardShadow: [
      BoxShadow(
        color: Color(0x120E1312),
        blurRadius: 20,
        offset: Offset(0, 4),
      ),
    ],
    microShadow: [
      BoxShadow(
        color: Color(0x0D0E1312),
        blurRadius: 3,
        offset: Offset(0, 1),
      ),
    ],
    categoryPalette: [
      CategoryColors(fill: Color(0xFFE6F0EC), ink: Color(0xFF2F6B57)),
      CategoryColors(fill: Color(0xFFE8EEF6), ink: Color(0xFF3C5C80)),
      CategoryColors(fill: Color(0xFFF3EBF3), ink: Color(0xFF6A4A6B)),
      CategoryColors(fill: Color(0xFFF6EFE4), ink: Color(0xFF7A5B32)),
      CategoryColors(fill: Color(0xFFEDF1E7), ink: Color(0xFF4F6438)),
      CategoryColors(fill: Color(0xFFF6EAEA), ink: Color(0xFF7C4444)),
    ],
  );

  /// Tokens do tema escuro.
  ///
  /// Duas diferenças **deliberadas**, não uma inversão do claro:
  /// 1. as sombras são listas vazias — sombra não se lê em canvas quase preto,
  ///    e fingir só suja a superfície. Profundidade vem dos três degraus de
  ///    superfície ([AppPalette.darkCanvas] → `darkCard` → `darkRaised`);
  /// 2. a marca sobe de `teal600` para `teal300/400`, porque `teal600` não
  ///    sustenta texto nem rótulo de preenchimento sobre canvas escuro.
  factory AppTokens.dark() => const AppTokens(
    moneyNeutral: AppPalette.darkInk,
    moneyPositive: AppPalette.teal300,
    moneyWarning: AppPalette.amber500,
    moneyOver: AppPalette.redDark,
    attention: AppPalette.amber500,
    attentionSubtle: Color(0x29D98A0B),
    brandSubtle: Color(0x2443A68D),
    brandBorder: Color(0x5743A68D),
    brandText: AppPalette.teal300,
    hairline: Color(0x14FFFFFF),
    hairlineStrong: Color(0x29FFFFFF),
    surfaceSunken: AppPalette.darkSunken,
    textSecondary: Color(0xC7F2F5F4),
    textMuted: Color(0x99F2F5F4),
    cardShadow: [],
    microShadow: [],
    categoryPalette: [
      CategoryColors(fill: Color(0x2943A68D), ink: Color(0xFF86C9B4)),
      CategoryColors(fill: Color(0x295A8ECC), ink: Color(0xFF93B4D8)),
      CategoryColors(fill: Color(0x29A06EA4), ink: Color(0xFFC3A0C4)),
      CategoryColors(fill: Color(0x29BA8E50), ink: Color(0xFFD2AE7C)),
      CategoryColors(fill: Color(0x2980A060), ink: Color(0xFFADC48F)),
      CategoryColors(fill: Color(0x29BA6E6E), ink: Color(0xFFD19C9C)),
    ],
  );

  /// Despesa e qualquer valor sem carga semântica. Igual ao texto primário.
  final Color moneyNeutral;

  /// Receita. Mesma cor da marca — como despesa é neutra, não faz falta uma
  /// terceira matiz, e receita na cor da marca reforça o propósito do produto.
  final Color moneyPositive;

  /// Orçamento próximo do limite (≥ 80%).
  final Color moneyWarning;

  /// Orçamento estourado (> 100%). Também usado em erro real.
  final Color moneyOver;

  final Color attention;
  final Color attentionSubtle;
  final Color brandSubtle;
  final Color brandBorder;

  /// Marca como cor de texto sobre o canvas (contraste ajustado por tema).
  final Color brandText;

  /// Mecanismo primário de separação: hairline de 1px.
  final Color hairline;
  final Color hairlineStrong;

  /// Preenchimento de campo/poço inerte.
  final Color surfaceSunken;

  final Color textSecondary;
  final Color textMuted;

  /// Elevação de card. **Vazia no escuro** — ver a doc da fábrica
  /// [AppTokens.dark].
  final List<BoxShadow> cardShadow;

  /// Elevação mínima (controles sobre superfície). Vazia no escuro.
  final List<BoxShadow> microShadow;

  /// Seis matizes de baixa croma para identidade de categoria.
  ///
  /// Única exceção sancionada à contenção de acento, porque o PRD dá `color` a
  /// cada categoria. Indexe por hash estável do id da categoria (ver
  /// [colorsForCategory]) para a cor sobreviver a renomeações.
  final List<CategoryColors> categoryPalette;

  /// Resolve a cor de uma categoria a partir do seu id, de forma estável.
  ///
  /// Usa o `hashCode` da string do id, então a mesma categoria sempre recebe a
  /// mesma matiz — inclusive depois de renomeada.
  CategoryColors colorsForCategory(String categoryId) {
    final index = categoryId.hashCode.abs() % categoryPalette.length;
    return categoryPalette[index];
  }

  @override
  AppTokens copyWith({
    Color? moneyNeutral,
    Color? moneyPositive,
    Color? moneyWarning,
    Color? moneyOver,
    Color? attention,
    Color? attentionSubtle,
    Color? brandSubtle,
    Color? brandBorder,
    Color? brandText,
    Color? hairline,
    Color? hairlineStrong,
    Color? surfaceSunken,
    Color? textSecondary,
    Color? textMuted,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? microShadow,
    List<CategoryColors>? categoryPalette,
  }) => AppTokens(
    moneyNeutral: moneyNeutral ?? this.moneyNeutral,
    moneyPositive: moneyPositive ?? this.moneyPositive,
    moneyWarning: moneyWarning ?? this.moneyWarning,
    moneyOver: moneyOver ?? this.moneyOver,
    attention: attention ?? this.attention,
    attentionSubtle: attentionSubtle ?? this.attentionSubtle,
    brandSubtle: brandSubtle ?? this.brandSubtle,
    brandBorder: brandBorder ?? this.brandBorder,
    brandText: brandText ?? this.brandText,
    hairline: hairline ?? this.hairline,
    hairlineStrong: hairlineStrong ?? this.hairlineStrong,
    surfaceSunken: surfaceSunken ?? this.surfaceSunken,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    cardShadow: cardShadow ?? this.cardShadow,
    microShadow: microShadow ?? this.microShadow,
    categoryPalette: categoryPalette ?? this.categoryPalette,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      moneyNeutral: Color.lerp(moneyNeutral, other.moneyNeutral, t)!,
      moneyPositive: Color.lerp(moneyPositive, other.moneyPositive, t)!,
      moneyWarning: Color.lerp(moneyWarning, other.moneyWarning, t)!,
      moneyOver: Color.lerp(moneyOver, other.moneyOver, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      attentionSubtle: Color.lerp(attentionSubtle, other.attentionSubtle, t)!,
      brandSubtle: Color.lerp(brandSubtle, other.brandSubtle, t)!,
      brandBorder: Color.lerp(brandBorder, other.brandBorder, t)!,
      brandText: Color.lerp(brandText, other.brandText, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      microShadow: t < 0.5 ? microShadow : other.microShadow,
      categoryPalette: _lerpPalette(other.categoryPalette, t),
    );
  }

  List<CategoryColors> _lerpPalette(List<CategoryColors> other, double t) {
    if (other.length != categoryPalette.length) {
      return t < 0.5 ? categoryPalette : other;
    }
    return [
      for (var i = 0; i < categoryPalette.length; i++)
        CategoryColors.lerp(categoryPalette[i], other[i], t),
    ];
  }
}
