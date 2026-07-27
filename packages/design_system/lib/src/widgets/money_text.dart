import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Carga semântica de um valor monetário.
///
/// Ver a regra central em `AppTokens`: despesa é o estado **neutro**, porque
/// aparece em ~90% das linhas — colorir isso é ruído, e vermelho-para-despesa
/// lê como erro na ação mais ordinária do produto.
enum MoneyTone {
  /// Despesa e qualquer valor sem carga. Sem cor.
  neutral,

  /// Receita. Cor da marca + sinal `+` explícito.
  positive,

  /// Orçamento próximo do limite (≥ 80%).
  warning,

  /// Orçamento estourado (> 100%) ou erro.
  over,
}

/// Tamanho tipográfico do valor.
enum MoneySize {
  /// 40px — o "momento alto". Um por tela, no máximo.
  balance,

  /// 22px — resumo de entradas/saídas.
  large,

  /// 15px — o da linha de transação.
  normal,

  /// 13px — metadado, total de dia.
  small,
}

/// Exibe um [Money] aplicando a semântica de cor e sinal do sistema.
///
/// Este widget existe para que **nenhum ponto de chamada** possa errar a regra:
/// a decisão de cor, peso e sinal mora aqui, não na tela. Figuras tabulares vêm
/// embutidas no estilo ([AppTypography.money] e afins), então colunas de
/// valores sempre alinham verticalmente.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    this.tone = MoneyTone.neutral,
    this.size = MoneySize.normal,
    this.withSymbol = false,
    super.key,
  });

  /// Atalho para uma despesa (tom neutro).
  const MoneyText.expense(
    this.amount, {
    this.size = MoneySize.normal,
    this.withSymbol = false,
    super.key,
  }) : tone = MoneyTone.neutral;

  /// Atalho para uma receita (marca + `+`).
  const MoneyText.income(
    this.amount, {
    this.size = MoneySize.normal,
    this.withSymbol = false,
    super.key,
  }) : tone = MoneyTone.positive;

  /// Valor a exibir.
  final Money amount;

  /// Carga semântica — define cor, peso e prefixo.
  final MoneyTone tone;

  /// Tamanho tipográfico.
  final MoneySize size;

  /// Inclui o símbolo da moeda (`R$`). Padrão `false`: em lista densa a moeda
  /// do espaço já é implícita.
  final bool withSymbol;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = switch (tone) {
      MoneyTone.neutral => tokens.moneyNeutral,
      MoneyTone.positive => tokens.moneyPositive,
      MoneyTone.warning => tokens.moneyWarning,
      MoneyTone.over => tokens.moneyOver,
    };
    final base = switch (size) {
      MoneySize.balance => AppTypography.balance,
      MoneySize.large => AppTypography.moneyLarge,
      MoneySize.normal => AppTypography.money,
      MoneySize.small => AppTypography.moneySmall,
    };

    // Tom não-neutro ganha peso, para que a cor nunca seja o único sinal.
    final style = tone == MoneyTone.neutral
        ? base.copyWith(color: color)
        : base.copyWith(color: color, fontWeight: FontWeight.w600);

    return Text(
      _label,
      style: style,
      semanticsLabel: amount.format(),
    );
  }

  /// Receita positiva recebe `+` explícito — o sinal é o sinal redundante que
  /// mantém o valor legível para quem não distingue as matizes.
  String get _label {
    final text = amount.format(withSymbol: withSymbol);
    final needsPlus = tone == MoneyTone.positive && !amount.isNegative;
    return needsPlus ? '+$text' : text;
  }
}
