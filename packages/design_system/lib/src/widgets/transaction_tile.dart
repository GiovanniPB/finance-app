import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'category_swatch.dart';
import 'money_text.dart';

/// Linha de transação — a superfície mais densa e mais usada do app.
///
/// Aplica a semântica de dinheiro via [MoneyText]: despesa neutra, receita na
/// marca com `+`. Suporta o estado [isPending], que um produto offline-first
/// precisa ter no design system em vez de enxertar depois: a transação já
/// existe localmente mas ainda não subiu para o servidor.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    required this.description,
    required this.amount,
    required this.icon,
    this.categoryId,
    this.categoryColorIndex,
    this.meta,
    this.isIncome = false,
    this.isPending = false,
    this.isSelected = false,
    this.onTap,
    super.key,
  });

  /// Descrição da transação (ex.: "Mercado Pão de Açúcar").
  final String description;

  final Money amount;

  /// Ícone da categoria.
  final IconData icon;

  /// Id da categoria, para resolver a matiz do swatch. `null` = cor da marca.
  final String? categoryId;

  /// Matiz escolhida para a categoria, quando houver. Vence o hash do id.
  final int? categoryColorIndex;

  /// Linha auxiliar (ex.: "Alimentação · Conta corrente").
  final String? meta;

  /// Receita em vez de despesa — muda cor e sinal do valor.
  final bool isIncome;

  /// Escrita localmente, ainda não sincronizada.
  final bool isPending;

  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metaText = isPending ? _pendingMeta : meta;
    final catId = categoryId;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: AppSizes.transactionRow,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        color: isSelected ? tokens.brandSubtle : null,
        child: Row(
          children: [
            if (catId == null)
              CategorySwatch.brand(icon: icon)
            else
              CategorySwatch(
                categoryId: catId,
                icon: icon,
                colorIndex: categoryColorIndex,
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleSmall,
                        ),
                      ),
                      if (isPending) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 13,
                          color: tokens.attention,
                        ),
                      ],
                    ],
                  ),
                  if (metaText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        metaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelMedium,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Pendente esmaece o valor: o dado é local, ainda não confirmado.
            Opacity(
              opacity: isPending ? 0.6 : 1,
              child: MoneyText(
                amount,
                tone: isIncome ? MoneyTone.positive : MoneyTone.neutral,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _pendingMeta {
    const suffix = 'aguardando envio';
    final base = meta;
    return base == null ? suffix : '$base · $suffix';
  }
}
