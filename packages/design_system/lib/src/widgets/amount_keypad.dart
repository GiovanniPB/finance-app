import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Teclado numérico próprio para entrada de valor.
///
/// Evita a troca de modo do teclado do sistema e, como o valor é um acumulador
/// de centavos, dispensa a tecla de vírgula — o separador decimal é implícito e
/// não pode ser posicionado errado. Uma tecla menos e um caso de erro menos.
///
/// Grade 3×4: os dígitos, um vazio que mantém o alinhamento, e o apagar.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    required this.onDigit,
    required this.onBackspace,
    super.key,
  });

  /// Dígito tocado, de 0 a 9. Quem consome acumula.
  final ValueChanged<int> onDigit;

  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) => Column(
    // Mede pelo conteúdo (4 × 46px + espaçamento), não pelo espaço disponível:
    // o teclado é sempre o mesmo tamanho, em folha ou em página.
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final rowDigits in const [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
      ])
        _KeyRow(
          children: [
            for (final digit in rowDigits)
              _Key.digit(label: '$digit', onTap: () => onDigit(digit)),
          ],
        ),
      _KeyRow(
        children: [
          const _Key.empty(),
          _Key.digit(label: '0', onTap: () => onDigit(0)),
          _Key.action(
            icon: Icons.backspace_outlined,
            onTap: onBackspace,
            semanticLabel: 'Apagar',
          ),
        ],
      ),
    ],
  );
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: children[i]),
        ],
      ],
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key.digit({required this.label, required this.onTap})
    : icon = null,
      semanticLabel = null;

  const _Key.action({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  }) : label = null;

  /// Espaço vazio que mantém o alinhamento da grade 3×4.
  const _Key.empty()
    : label = null,
      icon = null,
      onTap = null,
      semanticLabel = null;

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return const SizedBox(height: 46);

    return Material(
      color: context.tokens.surfaceSunken,
      borderRadius: AppRadii.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.brMd,
        child: SizedBox(
          height: 46,
          child: Center(
            child: label != null
                ? Text(
                    label!,
                    style: AppTypography.money.copyWith(
                      fontSize: 19,
                      color: context.colors.onSurface,
                    ),
                  )
                : Icon(
                    icon,
                    size: 19,
                    color: context.tokens.textMuted,
                    semanticLabel: semanticLabel,
                  ),
          ),
        ),
      ),
    );
  }
}
