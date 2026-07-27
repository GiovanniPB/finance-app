import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Chip de seleção de categoria.
///
/// Uma das duas únicas formas com pílula no sistema (a outra é avatar). Cor
/// sempre acompanhada de ícone, para que categoria nunca seja codificada só por
/// matiz.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    required this.label,
    required this.onSelected,
    this.icon,
    this.isSelected = false,
    super.key,
  });

  final String label;

  /// `null` desabilita o chip.
  final VoidCallback? onSelected;

  final IconData? icon;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isEnabled = onSelected != null;
    final fg = isSelected ? tokens.brandText : tokens.textSecondary;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: AppSpacing.xs + 2),
        ],
        Text(
          label,
          style: context.texts.labelMedium?.copyWith(
            color: fg,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: isEnabled ? 1 : 0.42,
      child: Material(
        color: isSelected
            ? tokens.brandSubtle
            : context.colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.brFull,
          side: BorderSide(
            color: isSelected ? context.colors.primary : tokens.hairline,
          ),
        ),
        child: InkWell(
          onTap: onSelected,
          customBorder: const RoundedRectangleBorder(
            borderRadius: AppRadii.brFull,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
