import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'money_text.dart';

/// Barra de progresso de orçamento com semântica por limiar.
///
/// A cor **sempre** vem acompanhada do rótulo de percentual — cor sozinha nunca
/// carrega o estado. Limiares (PRD RN-1.3):
///
/// - < 80% → marca;
/// - ≥ 80% → âmbar (atenção);
/// - > 100% → vermelho (estourado).
class BudgetProgress extends StatelessWidget {
  const BudgetProgress({
    required this.category,
    required this.spent,
    required this.limit,
    super.key,
  });

  /// Nome da categoria.
  final String category;

  final Money spent;
  final Money limit;

  /// Fração gasta do limite. Pode passar de 1 quando estourado.
  double get ratio {
    if (limit.amountMinor <= 0) return 0;
    return spent.amountMinor / limit.amountMinor;
  }

  /// Percentual inteiro para exibição.
  int get percent => (ratio * 100).round();

  /// Tom derivado do limiar.
  MoneyTone get tone {
    if (ratio > 1) return MoneyTone.over;
    if (ratio >= 0.8) return MoneyTone.warning;
    return MoneyTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final barColor = switch (tone) {
      MoneyTone.over => tokens.moneyOver,
      MoneyTone.warning => tokens.attention,
      MoneyTone.neutral || MoneyTone.positive => context.colors.primary,
    };
    final percentColor = switch (tone) {
      MoneyTone.over => tokens.moneyOver,
      MoneyTone.warning => tokens.moneyWarning,
      MoneyTone.neutral || MoneyTone.positive => tokens.textMuted,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.titleSmall,
              ),
            ),
            Text(
              '$percent%',
              style: context.texts.labelSmall?.copyWith(
                color: percentColor,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            MoneyText(spent, size: MoneySize.small),
            Text(' / ', style: context.texts.bodySmall),
            MoneyText(limit, size: MoneySize.small),
          ],
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            backgroundColor: tokens.surfaceSunken,
            valueColor: AlwaysStoppedAnimation(barColor),
            minHeight: 5,
          ),
        ),
      ],
    );
  }
}
