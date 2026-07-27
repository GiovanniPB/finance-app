import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Quadrado arredondado que identifica a categoria de uma transação.
///
/// A matiz vem de `AppTokens.colorsForCategory`, indexada por hash estável do
/// id — a cor sobrevive a renomeações. **Sempre acompanhada de ícone**: cor de
/// categoria nunca é o único sinal, então quem não distingue duas matizes ainda
/// lê a categoria pelo glifo.
class CategorySwatch extends StatelessWidget {
  const CategorySwatch({
    required this.categoryId,
    required this.icon,
    this.size = AppSizes.categorySwatch,
    super.key,
  });

  /// Cria um swatch na cor da marca — para receita, que não tem categoria de
  /// despesa.
  const CategorySwatch.brand({
    required this.icon,
    this.size = AppSizes.categorySwatch,
    super.key,
  }) : categoryId = null;

  /// Id da categoria. `null` usa a cor da marca.
  final String? categoryId;

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final id = categoryId;
    final fill = id == null
        ? tokens.brandSubtle
        : tokens.colorsForCategory(id).fill;
    final ink = id == null
        ? tokens.brandText
        : tokens.colorsForCategory(id).ink;

    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(color: fill, borderRadius: AppRadii.brMd),
      child: Center(
        child: Icon(icon, size: size * 0.5, color: ink),
      ),
    );
  }
}
