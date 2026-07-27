import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'category_form_controller.dart';
import 'category_icons.dart';

/// Cria uma categoria de usuário (RN-1.2).
///
/// Nome, ícone e matiz — nada mais. Subcategoria existe no schema
/// (`parent_category_id`) mas fica fora: hierarquia só compensa depois que
/// alguém tem categorias demais, e ninguém tem na primeira semana.
///
/// Devolve a categoria criada pelo `pop`, para quem abriu já sair com ela
/// selecionada em vez de ter de procurá-la na lista.
class CategoryFormSheet extends ConsumerWidget {
  const CategoryFormSheet({super.key});

  /// Abre a folha. Devolve o id da categoria criada, ou `null` se desistiu.
  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const CategoryFormSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(categoryFormControllerProvider);
    final controller = ref.read(categoryFormControllerProvider.notifier);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sheetPadding,
        AppSpacing.sm,
        AppSpacing.sheetPadding,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetGrabHandle(),
          Text(
            'Nova categoria',
            textAlign: TextAlign.center,
            style: context.texts.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          _Preview(
            name: state.trimmedName,
            iconKey: state.iconKey,
            colorIndex: state.colorIndex,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Nome',
            hint: 'Ex.: Academia',
            onChanged: controller.editName,
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.errorMessage!,
              key: const Key('category_form_error'),
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const _FieldLabel('Ícone'),
          _IconPicker(
            selected: state.iconKey,
            onSelected: controller.selectIcon,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _FieldLabel('Cor'),
          _ColorPicker(
            selected: state.colorIndex,
            onSelected: controller.selectColor,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            label: 'Criar categoria',
            isLoading: state.isSaving,
            onPressed: state.canSave
                ? () async {
                    final created = await controller.save();
                    if (created != null && context.mounted) {
                      Navigator.of(context).pop(created.id);
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(text, style: context.texts.labelMedium),
  );
}

/// Como a categoria vai aparecer na lista, montada enquanto se digita.
///
/// O swatch é o mesmo widget da linha de transação, então isto não é uma
/// aproximação do resultado: é o resultado.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.name,
    required this.iconKey,
    required this.colorIndex,
  });

  final String name;
  final String iconKey;
  final int? colorIndex;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      CategorySwatch(
        // Sem id ainda: a matiz vem da escolha, ou do nome como palpite estável
        // enquanto ninguém escolheu.
        categoryId: name,
        colorIndex: colorIndex,
        icon: CategoryIcons.resolve(iconKey),
      ),
      const SizedBox(width: AppSpacing.md),
      Text(
        name.isEmpty ? 'Sem nome' : name,
        style: context.texts.titleSmall?.copyWith(
          color: name.isEmpty ? context.tokens.textMuted : null,
        ),
      ),
    ],
  );
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (final key in CategoryIcons.selectable)
        _PickerCell(
          key: Key('icon_$key'),
          isSelected: key == selected,
          onTap: () => onSelected(key),
          child: Icon(
            CategoryIcons.resolve(key),
            size: 20,
            color: context.colors.onSurface,
          ),
        ),
    ],
  );
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelected});

  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var index = 0; index < tokens.categoryHues; index++)
          _PickerCell(
            key: Key('color_$index'),
            isSelected: index == selected,
            // Tocar a matiz escolhida desmarca: sem escolha, a cor sai do hash
            // do id, que é o comportamento das categorias de sistema.
            onTap: () => onSelected(index == selected ? null : index),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.colorsAt(index).fill,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                height: 20,
                width: 20,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.colorsAt(index).ink,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(height: 8, width: 8),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Célula quadrada de seleção, com o mesmo tratamento de foco dos chips.
class _PickerCell extends StatelessWidget {
  const _PickerCell({
    required this.isSelected,
    required this.onTap,
    required this.child,
    super.key,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: isSelected ? tokens.brandSubtle : tokens.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.brMd,
        side: BorderSide(
          color: isSelected ? context.colors.primary : tokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.brMd,
        child: SizedBox(height: 44, width: 44, child: Center(child: child)),
      ),
    );
  }
}
