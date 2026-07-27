import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monta [child] dentro do tema real do app.
///
/// Usar o tema de verdade (e não um `MaterialApp` cru) é o que torna os testes
/// de widget úteis aqui: os widgets leem cor de [AppTokens], então sem o tema
/// eles nem constroem — o que é exatamente o contrato que queremos verificar.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: child),
  ),
);

/// Cor efetiva do [Text] cujo conteúdo é [data].
Color textColor(WidgetTester tester, String data) {
  final widget = tester.widget<Text>(find.text(data));
  return widget.style!.color!;
}

/// Estilo efetivo do [Text] cujo conteúdo é [data].
TextStyle textStyleOf(WidgetTester tester, String data) {
  return tester.widget<Text>(find.text(data)).style!;
}
