import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Campo de texto do sistema.
///
/// Toda a decoração (raio, hairline, foco de 2px na marca, erro) vem do
/// `InputDecorationTheme`, não daqui — este widget só compõe rótulo, campo e
/// mensagem de erro com o espaçamento certo. Foco engrossa a borda; **sem glow,
/// sem anel**.
class AppTextField extends StatelessWidget {
  const AppTextField({
    this.label,
    this.hint,
    this.controller,
    this.errorText,
    this.enabled = true,
    this.keyboardType,
    this.onChanged,
    super.key,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? errorText;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final labelText = label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labelText != null) ...[
          Text(labelText, style: context.texts.labelMedium),
          const SizedBox(height: AppSpacing.xs + 1),
        ],
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: context.texts.bodyMedium,
          decoration: InputDecoration(hintText: hint, errorText: errorText),
        ),
      ],
    );
  }
}

/// Campo de valor monetário.
///
/// Alinhado à direita e em mono com figuras tabulares, para a vírgula decimal
/// cair onde o olho espera — igual à coluna de valores da lista. O símbolo da
/// moeda vive no prefixo, fora do texto editável, então nunca entra no que o
/// usuário digita.
class MoneyField extends StatelessWidget {
  const MoneyField({
    this.label,
    this.controller,
    this.errorText,
    this.enabled = true,
    this.currencySymbol = r'R$',
    this.onChanged,
    super.key,
  });

  final String? label;
  final TextEditingController? controller;
  final String? errorText;
  final bool enabled;

  /// Símbolo exibido como prefixo, fora do texto editável.
  final String currencySymbol;

  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final labelText = label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labelText != null) ...[
          Text(labelText, style: context.texts.labelMedium),
          const SizedBox(height: AppSpacing.xs + 1),
        ],
        TextField(
          controller: controller,
          enabled: enabled,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          style: AppTypography.money.copyWith(
            color: context.colors.onSurface,
            fontSize: 17,
          ),
          decoration: InputDecoration(
            errorText: errorText,
            hintText: '0,00',
            prefixIcon: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.sm,
              ),
              child: Text(
                currencySymbol,
                style: AppTypography.money.copyWith(
                  color: context.tokens.textMuted,
                  fontSize: 15,
                ),
              ),
            ),
            // BoxConstraints() sem limites remove o mínimo de 48px que o
            // Material aplica ao prefixIcon — aqui o prefixo é só o símbolo.
            prefixIconConstraints: const BoxConstraints(),
          ),
        ),
      ],
    );
  }
}
