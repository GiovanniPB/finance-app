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
///
/// ## Valor grande encolhe, não vaza
///
/// 40px mono cabe uns sete caracteres na largura de uma folha em tela de 390px.
/// A partir de `R$ 8.000,00` a linha estourava e o Flutter pintava a faixa de
/// overflow — em **qualquer** folha que usasse este widget, registro rápido
/// incluído. Um [FittedBox] resolve reduzindo a escala do número: o valor
/// continua legível e nunca é cortado, que é o oposto de um dígito escondido
/// atrás da borda.
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
      // `Flexible` + `scaleDown` em vez de `Expanded`: com valor curto o número
      // mantém o tamanho cheio e fica centrado ao lado do símbolo; só quando
      // não cabe é que a escala cede.
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            key: valueKey,
            maxLines: 1,
            style: AppTypography.balance.copyWith(
              color: context.colors.onSurface,
            ),
          ),
        ),
      ),
    ],
  );
}
