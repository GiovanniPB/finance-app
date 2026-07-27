import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/domain/category.dart';
import '../../categories/presentation/categories_providers.dart';
import '../../categories/presentation/category_icons.dart';
import '../domain/transaction.dart';
import 'quick_entry_controller.dart';

/// Registro rápido de gasto ou receita.
///
/// Tudo exceto valor e categoria vem pré-preenchido: data é hoje, tipo é
/// despesa (o caso esmagadoramente mais comum), espaço é o ativo. Caminho
/// mínimo: **digitar valor → tocar categoria → Salvar**.
class QuickEntrySheet extends ConsumerWidget {
  const QuickEntrySheet({super.key});

  /// Abre o sheet. Devolve `true` quando uma transação foi salva.
  static Future<bool?> show(BuildContext context) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const QuickEntrySheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(quickEntryControllerProvider);
    final controller = ref.read(quickEntryControllerProvider.notifier);
    final categories =
        ref.watch(categoriesProvider).asData?.value ?? const <Category>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sheetPadding,
        AppSpacing.sm,
        AppSpacing.sheetPadding,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _GrabHandle(),
          AppSegmentedControl(
            segments: const ['Despesa', 'Receita'],
            selectedIndex: state.type == TransactionType.income ? 1 : 0,
            onChanged: (index) => controller.selectType(
              index == 1 ? TransactionType.income : TransactionType.expense,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _AmountDisplay(label: state.amountLabel),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.errorMessage!,
              key: const Key('quick_entry_error'),
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _CategoryPicker(
            categories: categories,
            selectedId: state.categoryId,
            onSelected: controller.selectCategory,
          ),
          const SizedBox(height: AppSpacing.lg),
          _Keypad(
            onDigit: controller.pressDigit,
            onBackspace: controller.pressBackspace,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Salvar',
            isLoading: state.isSaving,
            onPressed: state.canSave
                ? () async {
                    final saved = await controller.save();
                    if (saved && context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(
      top: AppSpacing.xs,
      bottom: AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: context.tokens.hairlineStrong,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// O momento alto deste sheet: o valor sendo digitado, em 40px mono tabular.
class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          right: AppSpacing.xs,
        ),
        child: Text(
          r'R$',
          style: AppTypography.money.copyWith(color: context.tokens.textMuted),
        ),
      ),
      Text(
        label,
        key: const Key('quick_entry_amount'),
        style: AppTypography.balance.copyWith(color: context.colors.onSurface),
      ),
    ],
  );
}

/// Chips de categoria em rolagem horizontal.
///
/// As de sistema vêm primeiro (o repositório já ordena assim), o que aproxima a
/// lista das mais usadas sem precisar de histórico ainda.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Text(
        'Sincronizando categorias…',
        style: context.texts.bodySmall,
      );
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

/// Teclado numérico próprio.
///
/// Evita a troca de modo do teclado do sistema e, como o valor é um acumulador
/// de centavos, dispensa a tecla de vírgula — o separador decimal é implícito e
/// não pode ser posicionado errado.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) => Column(
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
