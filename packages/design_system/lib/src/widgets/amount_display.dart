import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Valor em digitação, em 40px mono tabular, com o símbolo como prefixo fixo.
///
/// É o **momento alto** de qualquer folha de entrada de valor: registro rápido
/// e limite de orçamento usam o mesmo tratamento, então o gesto de digitar
/// valor se parece consigo mesmo em todo o app.
///
/// O símbolo é prefixo separado, em tom apagado, porque quem digita está lendo
/// o número — a moeda é contexto, não conteúdo.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({required this.label, this.symbol = r'R$', super.key});

  /// Chave do texto do valor. Os testes leem o valor exibido por ela.
  static const valueKey = Key('amount_display_value');

  /// Valor já formatado, sem símbolo (ex.: `1.234,56`).
  final String label;

  /// Símbolo da moeda, em prefixo.
  final String symbol;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          right: AppSpacing.xs,
        ),
        child: Text(
          symbol,
          style: AppTypography.money.copyWith(color: context.tokens.textMuted),
        ),
      ),
      Text(
        label,
        key: valueKey,
        style: AppTypography.balance.copyWith(color: context.colors.onSurface),
      ),
    ],
  );
}
