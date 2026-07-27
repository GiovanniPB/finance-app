import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Barra de progresso de **meta de poupança** — a contraparte de
/// `BudgetProgress`, com semântica oposta.
///
/// ## Por que não é o mesmo widget do orçamento
///
/// As duas barras têm a mesma forma e significados invertidos: encher um
/// orçamento é ruim (100% é o limite estourado), encher uma meta é a conquista
/// (100% é o objetivo atingido). Um widget só, com um `bool isGoal`, deixaria a
/// decisão de cor a cargo de quem chama — e é exatamente esse tipo de escolha
/// que o design system existe para tirar do ponto de chamada.
///
/// Dois sinais separam as duas barras, e nenhum deles é sutil:
///
///  • **Meta nunca usa âmbar nem vermelho.** O preenchimento é sempre a marca.
/// Meta atrasada não é erro — é informação, e o atraso se diz em texto. É a
/// mesma razão pela qual despesa não é vermelha (ver a doc de `AppTokens`).
///  • **Só meta tem marca de ritmo** ([paceRatio]): um tick de 2px mostrando
/// onde o prazo diria que se estaria hoje. Sem prazo não há ritmo, e o trilho
/// fica limpo.
///
/// O trilho é mais alto que o do orçamento (8px contra 5px) porque na tela de
/// Poupança o progresso **é** o conteúdo, enquanto na home a barra de orçamento
/// é informação secundária sob um saldo que já é o momento alto.
class SavingsProgress extends StatelessWidget {
  const SavingsProgress({
    required this.ratio,
    this.paceRatio,
    this.semanticLabel,
    super.key,
  });

  /// Fração do alvo já guardada. Pode passar de 1 — guardar além do alvo é bom,
  /// e a barra simplesmente satura.
  final double ratio;

  /// Fração do prazo já decorrida, de 0 a 1. **Nula quando a meta não tem
  /// prazo**, e aí nenhuma marca é desenhada.
  final double? paceRatio;

  /// Descrição para leitor de tela. A barra é redundante por construção (o
  /// número e a frase de status ficam ao lado), então isto é complemento.
  final String? semanticLabel;

  /// Altura do trilho. Ver a doc da classe para o porquê de ser maior que a do
  /// orçamento.
  static const trackHeight = 8.0;

  static const _tickWidth = 2.0;

  /// Quanto o tick avança além do trilho, para cima e para baixo.
  static const _tickOverhang = 4.0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final pace = paceRatio;

    return Semantics(
      label: semanticLabel,
      value: '${(ratio * 100).round()}%',
      child: SizedBox(
        // O tick extrapola o trilho, então a caixa precisa caber o excesso —
        // senão ele é cortado e lê como defeito de renderização.
        height: trackHeight + _tickOverhang * 2,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(trackHeight / 2),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    backgroundColor: tokens.surfaceSunken,
                    // Sempre a marca. Nunca âmbar, nunca vermelho.
                    valueColor: AlwaysStoppedAnimation(context.colors.primary),
                    minHeight: trackHeight,
                  ),
                ),
                if (pace != null)
                  Positioned(
                    left:
                        (constraints.maxWidth - _tickWidth) *
                        pace.clamp(0.0, 1.0),
                    top: -_tickOverhang,
                    bottom: -_tickOverhang,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.hairlineStrong,
                        borderRadius: BorderRadius.circular(_tickWidth / 2),
                      ),
                      child: const SizedBox(width: _tickWidth),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Selo de meta concluída.
///
/// O único lugar do app em que a marca preenche um contorno inteiro para dizer
/// "deu certo". Um orçamento em 100% recebe vermelho; uma meta em 100% recebe
/// isto — dois estados cheios, dois significados, e nenhuma ambiguidade.
class CompletionSeal extends StatelessWidget {
  const CompletionSeal({this.label = 'Concluída', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.brandSubtle,
        border: Border.all(color: tokens.brandBorder),
        borderRadius: AppRadii.brFull,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: tokens.brandText),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label.toUpperCase(),
              style: context.texts.labelSmall?.copyWith(
                color: tokens.brandText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
