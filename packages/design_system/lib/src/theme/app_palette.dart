import 'package:flutter/material.dart';

/// Rampas de cor cruas do sistema de design.
///
/// **Não consuma esta classe na UI.** Widgets leem apenas os papéis semânticos
/// (`ColorScheme` e `AppTokens`); esta rampa existe só para montá-los. Trocar
/// uma cor aqui deve refletir em todo o app sem tocar em nenhum widget.
abstract final class AppPalette {
  // -------------------------------------------------------------------------
  // Marca — teal ancorado em #1E6F5C (semente original do app). Mantida de
  // propósito: diferencia do roxo Nubank e do laranja Itaú/Inter.
  // -------------------------------------------------------------------------
  static const teal50 = Color(0xFFE9F6F2);
  static const teal100 = Color(0xFFC8E9E0);
  static const teal200 = Color(0xFF9FD8C9);
  static const teal300 = Color(0xFF6FC2AE);
  static const teal400 = Color(0xFF43A68D);
  static const teal500 = Color(0xFF2A8770);
  static const teal600 = Color(0xFF1E6F5C);
  static const teal700 = Color(0xFF175845);
  static const teal800 = Color(0xFF114235);
  static const teal900 = Color(0xFF0B2C24);
  static const teal950 = Color(0xFF061914);

  // -------------------------------------------------------------------------
  // Neutros — levemente esverdeados, para ficarem na família da marca.
  // -------------------------------------------------------------------------
  static const ink50 = Color(0xFFF7F9F8);
  static const ink100 = Color(0xFFEEF2F0);
  static const ink200 = Color(0xFFE1E6E4);
  static const ink300 = Color(0xFFC7CFCC);
  static const ink400 = Color(0xFFA0AAA7);
  static const ink500 = Color(0xFF7B8582);
  static const ink600 = Color(0xFF5C6764);
  static const ink700 = Color(0xFF414A48);
  static const ink800 = Color(0xFF2A3231);
  static const ink900 = Color(0xFF1A201F);
  static const ink950 = Color(0xFF0E1312);
  static const white = Color(0xFFFFFFFF);

  // -------------------------------------------------------------------------
  // Âmbar — atenção de orçamento. Segundo e último acento.
  // -------------------------------------------------------------------------
  static const amber100 = Color(0xFFFDF0D5);
  static const amber500 = Color(0xFFD98A0B);
  static const amber600 = Color(0xFFB36F06);
  static const amber700 = Color(0xFF8A5504);

  // -------------------------------------------------------------------------
  // Vermelho — RESERVADO a erro real e orçamento estourado. Nunca despesa.
  // -------------------------------------------------------------------------
  static const red100 = Color(0xFFFBE6E3);
  static const red500 = Color(0xFFCC3D2E);
  static const red600 = Color(0xFFAD2E21);
  static const red700 = Color(0xFF8A2318);
  static const redDark = Color(0xFFF2695A);

  // -------------------------------------------------------------------------
  // Superfícies do tema escuro. Três degraus: o escuro expressa profundidade
  // por degrau de superfície, não por sombra (ver `AppTokens.cardShadow`).
  // -------------------------------------------------------------------------
  static const darkCanvas = Color(0xFF0C100F);
  static const darkCard = Color(0xFF151A19);
  static const darkRaised = Color(0xFF1D2422);
  static const darkSunken = Color(0xFF101514);
  static const darkInk = Color(0xFFF2F5F4);
}
