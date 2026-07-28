import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/category.dart';
import 'category_form_controller.dart';
import 'category_icons.dart';

/// Cria ou edita uma categoria de usuário (RN-1.2).
///
/// Nome, ícone e matiz — nada mais. Subcategoria existe no schema
/// (`parent_category_id`) mas fica fora: hierarquia só compensa depois que
/// alguém tem categorias demais, e ninguém tem na primeira semana.
///
/// Devolve a categoria gravada pelo `pop`, para quem abriu já sair com ela
/// selecionada em vez de ter de procurá-la na lista.
///
/// `ConsumerStatefulWidget` por causa do campo de nome: editar precisa do texto
/// já preenchido, e isso exige um `TextEditingController` com dono — o mesmo
/// motivo da folha de edição de lançamento.
class CategoryFormSheet extends ConsumerStatefulWidget {
  const CategoryFormSheet({this.editing, super.key});

  /// Categoria a editar. Nula cria uma nova.
  final Category? editing;

  /// Abre a folha. Devolve o id da categoria gravada, ou `null` se desistiu.
  static Future<String?> show(BuildContext context, {Category? editing}) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => CategoryFormSheet(editing: editing),
      );

  @override
  ConsumerState<CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<CategoryFormSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = categoryFormControllerProvider(widget.editing);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

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
            state.isEditing ? 'Editar categoria' : 'Nova categoria',
            textAlign: TextAlign.center,
            style: context.texts.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          _Preview(
            name: state.trimmedName,
            iconKey: state.iconKey,
            colorIndex: state.colorIndex,
            categoryId: widget.editing?.id,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Nome',
            hint: 'Ex.: Academia',
            controller: _name,
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
            key: const Key('category_form_save'),
            label: state.isEditing ? 'Salvar categoria' : 'Criar categoria',
            isLoading: state.isSaving,
            onPressed: state.canSave
                ? () async {
                    final saved = await controller.save();
                    if (saved != null && context.mounted) {
                      Navigator.of(context).pop(saved.id);
                    }
                  }
                : null,
          ),
          if (state.isEditing) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const Key('category_delete'),
              label: 'Excluir categoria',
              variant: AppButtonVariant.ghost,
              onPressed: state.isSaving ? null : _confirmDelete,
            ),
          ],
        ],
      ),
    );
  }

  /// Confirma e remove.
  ///
  /// A recusa por categoria em uso **não** é pré-checada: o repository já
  /// devolve a contagem na mensagem ("3 lançamentos usam esta categoria…"), e
  /// ela aparece na folha, que fica aberta. Pré-checar economizaria um toque ao
  /// custo de duplicar essa frase em dois lugares.
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir esta categoria?'),
        content: const Text(
          'Só sai categoria que nenhum lançamento usa. Isso não pode ser '
          'desfeito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_delete_category'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final removed = await ref
        .read(categoryFormControllerProvider(widget.editing).notifier)
        .remove();
    if (removed && mounted) Navigator.of(context).pop();
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
    this.categoryId,
  });

  final String name;
  final String iconKey;
  final int? colorIndex;

  /// Id da categoria em edição, quando há uma. Nulo ao criar.
  final String? categoryId;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      CategorySwatch(
        // Editando, a matiz sem escolha explícita sai do hash do **id** — que é
        // o que a lista vai mostrar. Criando não há id ainda, então o nome
        // serve de palpite estável enquanto ninguém escolheu.
        categoryId: categoryId ?? name,
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
