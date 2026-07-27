import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Variante visual do botão.
enum AppButtonVariant {
  /// Ação principal da tela. Preenchimento na marca.
  primary,

  /// Ação alternativa. Contorno hairline.
  secondary,

  /// Ação terciária/navegacional. Sem preenchimento nem borda.
  ghost,

  /// Ação destrutiva. Preenchimento no vermelho reservado.
  danger,
}

/// Botão do sistema.
///
/// Estados de hover e press são **só de cor** — sem escala e sem elevação:
/// escala briga com o alvo de 48dp e lê como tremor quando o botão está numa
/// lista. Quando [isLoading] é `true` o botão fica desabilitado e troca o
/// rótulo por um indicador, preservando a largura.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    super.key,
  });

  /// Rótulo em sentence case. Prefira verbo específico ("Salvar") a genérico
  /// ("Enviar", "Continuar").
  final String label;

  /// `null` desabilita o botão.
  final VoidCallback? onPressed;

  final AppButtonVariant variant;

  /// Ícone opcional à esquerda do rótulo.
  final IconData? icon;

  /// Mostra indicador de progresso e desabilita a interação.
  final bool isLoading;

  /// Ocupa toda a largura disponível. `false` para o botão caber no texto.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;
    final child = isLoading
        ? _Spinner(variant: variant)
        : _Label(label: label, icon: icon);

    final button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
      AppButtonVariant.danger => FilledButton(
        onPressed: effectiveOnPressed,
        style: FilledButton.styleFrom(
          backgroundColor: context.colors.error,
          foregroundColor: context.colors.onError,
        ),
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
      AppButtonVariant.ghost => TextButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.variant});

  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final color = switch (variant) {
      AppButtonVariant.primary => context.colors.onPrimary,
      AppButtonVariant.danger => context.colors.onError,
      AppButtonVariant.secondary ||
      AppButtonVariant.ghost => context.colors.primary,
    };
    return SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}
