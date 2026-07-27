import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Controle segmentado de duas ou mais opções curtas.
///
/// Usado no registro rápido para alternar Despesa/Receita. O segmento ativo
/// sobe de superfície (card sobre poço) em vez de mudar de cor — mantém a
/// contenção de acento e funciona igual nos dois temas.
class AppSegmentedControl extends StatelessWidget {
  const AppSegmentedControl({
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  /// Rótulos, em sentence case.
  final List<String> segments;

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: AppRadii.brMd,
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++)
            Expanded(
              child: _Segment(
                label: segments[i],
                isSelected: i == selectedIndex,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.easeOut,
        height: 38,
        decoration: BoxDecoration(
          color: isSelected ? context.colors.surfaceContainerLow : null,
          borderRadius: AppRadii.brSm,
          boxShadow: isSelected ? tokens.microShadow : null,
        ),
        child: Center(
          child: Text(
            label,
            style: context.texts.titleSmall?.copyWith(
              color: isSelected ? context.colors.onSurface : tokens.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
