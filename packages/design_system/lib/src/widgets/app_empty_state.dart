import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

/// Estado vazio.
///
/// **Sempre nomeia a próxima ação.** "Nenhum dado" sozinho é um beco sem saída;
/// por isso [actionLabel] e [onAction] existem, e o corpo é escrito para
/// convidar em vez de informar uma ausência.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;

  /// Título curto, sentence case (ex.: "Nenhum gasto em julho").
  final String title;

  /// Uma frase que aponta o próximo passo.
  final String message;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = actionLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppRadii.brXl,
        border: Border.all(color: tokens.hairlineStrong),
      ),
      child: Column(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: tokens.brandSubtle,
              borderRadius: AppRadii.brLg,
            ),
            child: Center(
              child: Icon(icon, size: 22, color: tokens.brandText),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.texts.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.texts.bodySmall,
          ),
          if (label != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: label, onPressed: onAction, expand: false),
          ],
        ],
      ),
    );
  }
}
