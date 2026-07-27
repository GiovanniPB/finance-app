import 'package:flutter/material.dart';

/// Tipografia do sistema: duas famílias, dois papéis.
///
/// - [sansFamily] — toda prosa, rótulo e controle.
/// - [monoFamily] — **todo** numeral que representa dinheiro.
///
/// ## Fontes ainda não empacotadas
///
/// Os binários de Inter e IBM Plex Mono não estão no repositório. Declarar o
/// nome de uma família não registrada é seguro no Flutter: cai silenciosamente
/// na fonte da plataforma. Para valer, adicione os arquivos em
/// `assets/fonts/` e declare a seção `fonts:` no `pubspec.yaml` do pacote.
///
/// `FontFeature.tabularFigures()` funciona de qualquer forma — SF (iOS) e
/// Roboto (Android) suportam o recurso `tnum`.
abstract final class AppTypography {
  static const sansFamily = 'Inter';
  static const monoFamily = 'IBMPlexMono';

  /// O "momento alto": exatamente **um** elemento por tela pode usar este
  /// estilo. Na home do espaço é o saldo do mês; no registro rápido é o valor
  /// sendo digitado. É assim que a hierarquia nasce de contraste de escala em
  /// vez de decoração.
  static const balance = TextStyle(
    fontFamily: monoFamily,
    fontSize: 40,
    height: 1.05,
    letterSpacing: -1.4,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Valor monetário destacado (resumo de entradas/saídas).
  static const moneyLarge = TextStyle(
    fontFamily: monoFamily,
    fontSize: 22,
    height: 1.18,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Valor monetário padrão — o da linha de transação.
  static const money = TextStyle(
    fontFamily: monoFamily,
    fontSize: 15,
    height: 1.33,
    letterSpacing: -0.1,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Valor monetário auxiliar (metadado, total de dia).
  static const moneySmall = TextStyle(
    fontFamily: monoFamily,
    fontSize: 13,
    height: 1.31,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Monta o [TextTheme] de prosa: [primary] para texto de conteúdo, [muted]
  /// para rótulo e texto auxiliar.
  static TextTheme textTheme(Color primary, Color muted) => TextTheme(
    // display — cabeçalho de tela
    displaySmall: TextStyle(
      fontFamily: sansFamily,
      fontSize: 26,
      height: 1.19,
      letterSpacing: -0.5,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    // title — título de seção grande
    headlineSmall: TextStyle(
      fontFamily: sansFamily,
      fontSize: 20,
      height: 1.25,
      letterSpacing: -0.2,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    // heading — título de item
    titleMedium: TextStyle(
      fontFamily: sansFamily,
      fontSize: 17,
      height: 1.29,
      letterSpacing: -0.1,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    titleSmall: TextStyle(
      fontFamily: sansFamily,
      fontSize: 14,
      height: 1.29,
      fontWeight: FontWeight.w500,
      color: primary,
    ),
    bodyLarge: TextStyle(
      fontFamily: sansFamily,
      fontSize: 15,
      height: 1.47,
      color: primary,
    ),
    bodyMedium: TextStyle(
      fontFamily: sansFamily,
      fontSize: 15,
      height: 1.47,
      color: primary,
    ),
    bodySmall: TextStyle(
      fontFamily: sansFamily,
      fontSize: 13,
      height: 1.38,
      color: muted,
    ),
    // labelLarge é o estilo de texto de botão no Material.
    labelLarge: TextStyle(
      fontFamily: sansFamily,
      fontSize: 15,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    labelMedium: TextStyle(
      fontFamily: sansFamily,
      fontSize: 12,
      height: 1.33,
      fontWeight: FontWeight.w500,
      color: muted,
    ),
    // micro — uppercase é aplicado pelo widget, não pelo token.
    labelSmall: TextStyle(
      fontFamily: sansFamily,
      fontSize: 11,
      height: 1.27,
      letterSpacing: 0.4,
      fontWeight: FontWeight.w600,
      color: muted,
    ),
  );
}
