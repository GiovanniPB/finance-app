import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Alça de arraste no topo de uma bottom sheet.
///
/// Sinaliza "isto se puxa para fechar" sem gastar um botão. Fica em hairline
/// forte, não em cor de acento: é affordance, não conteúdo.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.md),
    decoration: BoxDecoration(
      color: context.tokens.hairlineStrong,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
