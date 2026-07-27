import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'money_text.dart';

/// Cabeçalho de saldo — **o momento alto da tela**.
///
/// Usa [MoneySize.balance] (40px). Só um elemento por tela pode fazer isso; é
/// como a hierarquia nasce de contraste de escala em vez de decoração. Se outro
/// widget na mesma tela também usar esse tamanho, um dos dois está errado.
class BalanceHeader extends StatelessWidget {
  const BalanceHeader({
    required this.label,
    required this.amount,
    this.delta,
    this.caption,
    super.key,
  });

  /// Rótulo acima do valor (ex.: "Saldo de julho").
  final String label;

  final Money amount;

  /// Variação relativa já formatada (ex.: "+8,2%"). Progresso relativo, não
  /// montante — o PRD §8.4 proíbe expor valor absoluto por padrão no social.
  final String? delta;

  /// Texto auxiliar à direita do delta (ex.: "vs. junho · restam 4 dias").
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final deltaText = delta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.texts.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        MoneyText(amount, size: MoneySize.balance, withSymbol: true),
        if (deltaText != null || caption != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (deltaText != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.brandSubtle,
                    borderRadius: AppRadii.brXs,
                  ),
                  child: Text(
                    deltaText,
                    style: context.texts.labelSmall?.copyWith(
                      color: tokens.moneyPositive,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              if (caption != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
