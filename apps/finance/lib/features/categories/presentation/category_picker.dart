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
    this.onCreate,
    this.emptyMessage = 'Nenhuma categoria sincronizada ainda.',
    super.key,
  });

  final List<Category> categories;
  final String? selectedId;

  /// Recebe `null` quando a categoria selecionada é tocada de novo.
  final ValueChanged<String?> onSelected;

  /// Abre a criação de categoria. Quando nulo, o chip "Nova" não aparece.
  final VoidCallback? onCreate;

  /// Texto exibido quando não há categoria para escolher.
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final create = onCreate;

    if (categories.isEmpty) {
      if (create == null) {
        return Text(emptyMessage, style: context.texts.bodySmall);
      }
      // O app não distingue "ainda sincronizando" de "não existe nenhuma", e um
      // "Sincronizando…" eterno prende quem está com o sync mal configurado —
      // sem categoria não se salva lançamento. Diz o que se sabe e dá a saída.
      return Row(
        children: [
          Expanded(
            child: Text(emptyMessage, style: context.texts.bodySmall),
          ),
          const SizedBox(width: AppSpacing.sm),
          CategoryChip(
            key: const Key('create_category'),
            label: 'Nova',
            icon: Icons.add,
            onSelected: create,
          ),
        ],
      );
    }

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = category.id == selectedId;
                    return CategoryChip(
                      label: category.name,
                      icon: CategoryIcons.resolve(category.iconKey),
                      isSelected: isSelected,
                      onSelected: () =>
                          onSelected(isSelected ? null : category.id),
                    );
                  },
                ),
                // O chip cortado contra o "Nova" ancorado lia como defeito de
                // renderização. O desvanecimento diz "há mais coisa ao lado".
                const Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: ScrollEdgeFade(axis: Axis.horizontal),
                ),
              ],
            ),
          ),
          if (create != null) ...[
            const SizedBox(width: AppSpacing.sm),
            // Fora da rolagem, e não no fim da fila: com as dez categorias de
            // sistema, um chip no fim exigiria seis arrastes para ser achado.
            // Ancorado à direita fica sempre visível sem roubar a primeira
            // posição, que é a mais usada.
            CategoryChip(
              key: const Key('create_category'),
              label: 'Nova',
              icon: Icons.add,
              onSelected: create,
            ),
          ],
        ],
      ),
    );
  }
}
