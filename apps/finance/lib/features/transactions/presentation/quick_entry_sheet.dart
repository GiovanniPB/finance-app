import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/domain/category.dart';
import '../../categories/presentation/categories_providers.dart';
import '../../categories/presentation/category_form_sheet.dart';
import '../../categories/presentation/category_picker.dart';
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
          const SheetGrabHandle(),
          AppSegmentedControl(
            segments: const ['Despesa', 'Receita'],
            selectedIndex: state.type == TransactionType.income ? 1 : 0,
            onChanged: (index) => controller.selectType(
              index == 1 ? TransactionType.income : TransactionType.expense,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AmountDisplay(label: state.amountLabel),
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
          CategoryPicker(
            categories: categories,
            selectedId: state.categoryId,
            onSelected: controller.selectCategory,
            // Criar já seleciona a categoria nova: quem parou para criá-la é
            // porque quer usá-la neste lançamento.
            onCreate: () async {
              final created = await CategoryFormSheet.show(context);
              if (created != null) controller.selectCategory(created);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AmountKeypad(
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
