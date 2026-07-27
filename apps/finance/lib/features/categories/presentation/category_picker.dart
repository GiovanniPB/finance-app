import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/category.dart';
import 'category_icons.dart';

/// Chips de categoria em rolagem horizontal.
///
/// As de sistema vêm primeiro (o repositório já ordena assim), o que aproxima a
/// lista das mais usadas sem precisar de histórico ainda.
///
/// Compartilhado entre o registro rápido e o formulário de orçamento: escolher
/// categoria é o mesmo gesto nos dois, e deve parecer o mesmo.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.emptyMessage = 'Sincronizando categorias…',
    super.key,
  });

  final List<Category> categories;
  final String? selectedId;

  /// Recebe `null` quando a categoria selecionada é tocada de novo.
  final ValueChanged<String?> onSelected;

  /// Texto exibido quando não há categoria para escolher.
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Text(emptyMessage, style: context.texts.bodySmall);
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category.id == selectedId;
          return CategoryChip(
            label: category.name,
            icon: CategoryIcons.resolve(category.iconKey),
            isSelected: isSelected,
            onSelected: () => onSelected(isSelected ? null : category.id),
          );
        },
      ),
    );
  }
}
