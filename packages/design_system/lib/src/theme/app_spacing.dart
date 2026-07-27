import 'package:flutter/material.dart';

/// Escala de espaçamento: base 4px estrita, com um micro-passo de 2px.
///
/// Deliberadamente **curta** (11 valores). O Flutter não tem cascata: cada
/// padding arbitrário vira um número fixo sem lugar central para corrigir
/// depois. Uma rampa larga é barata em CSS e caríssima em Dart.
///
/// **O ritmo não é uniforme.** Mesmos tokens, densidades diferentes por
/// superfície: a home respira em 24–32, a lista comprime em 12–16. Padding
/// uniforme em tudo é o caminho mais curto para parecer template.
abstract final class AppSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;
  static const giant = 48.0;
  static const colossal = 64.0;

  /// Padding horizontal padrão da borda da tela (mobile).
  static const double screenGutter = lg;

  /// Padding interno de card.
  static const double cardPadding = lg;

  /// Padding interno de bottom sheet.
  static const double sheetPadding = xl;
}

/// Raios de canto. **Nunca uniformes**: quanto maior a superfície, mais suave o
/// canto — a forma carrega hierarquia. Pílula só em avatar e chip de filtro.
abstract final class AppRadii {
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 10.0;
  static const lg = 12.0;
  static const xl = 16.0;
  static const xxl = 24.0;
  static const full = 9999.0;

  static const brXs = BorderRadius.all(Radius.circular(xs));
  static const brSm = BorderRadius.all(Radius.circular(sm));
  static const brMd = BorderRadius.all(Radius.circular(md));
  static const brLg = BorderRadius.all(Radius.circular(lg));
  static const brXl = BorderRadius.all(Radius.circular(xl));
  static const brFull = BorderRadius.all(Radius.circular(full));

  /// Cantos superiores de bottom sheet.
  static const brSheet = BorderRadius.vertical(top: Radius.circular(xxl));
}

/// Dimensões fixas de layout.
abstract final class AppSizes {
  /// Altura da linha de transação — densa, mas ainda tocável.
  static const transactionRow = 56.0;

  /// Alvo mínimo de toque. Nada interativo abaixo disso.
  static const touchTarget = 48.0;

  /// Altura da bottom nav.
  static const bottomNav = 64.0;

  /// Lado do swatch de categoria na linha de transação.
  static const categorySwatch = 34.0;

  /// Altura padrão de botão.
  static const buttonHeight = 48.0;

  /// Altura padrão de campo de formulário.
  static const fieldHeight = 48.0;
}

/// Durações e curvas de movimento.
///
/// Só propriedades amigáveis ao compositor (opacity e transform). Sem bounce,
/// sem spring. Estados de press são **só de cor**: escala briga com o alvo de
/// 48dp e lê como tremor numa lista.
abstract final class AppMotion {
  static const pressed = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 180);
  static const theme = Duration(milliseconds: 200);
  static const sheet = Duration(milliseconds: 240);

  static const Curve easeOut = Curves.easeOut;
  static const Curve easeOutExpo = Curves.easeOutExpo;
}
