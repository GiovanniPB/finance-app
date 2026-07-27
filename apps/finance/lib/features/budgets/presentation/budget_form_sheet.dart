import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/domain/category.dart';
import '../../categories/presentation/categories_providers.dart';
import '../../categories/presentation/category_picker.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/budget.dart';
import 'budget_form_controller.dart';
import 'budgets_providers.dart';

/// Define ou ajusta o limite de gasto de uma categoria no mês em foco.
///
/// Mesmo gesto do registro rápido — valor no teclado próprio, categoria em chip
/// — porque definir limite é a mesma operação mental de registrar gasto, com um
/// sinal invertido. Reaproveitar o gesto é o que faz o app parecer um só.
///
/// A folha só trata orçamento **mensal**: é o único período que a Fase 0 exibe
/// (ver `budgetUsageProvider`).
class BudgetFormSheet extends ConsumerWidget {
  const BudgetFormSheet({this.editing, super.key});

  /// Orçamento em edição. Nulo abre a folha para um limite novo.
  final Budget? editing;

  /// Abre a folha. Devolve `true` quando o limite foi salvo ou removido.
  static Future<bool?> show(BuildContext context, {Budget? editing}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => BudgetFormSheet(editing: editing),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = budgetFormControllerProvider(editing);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final month = ref.watch(focusedMonthProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sheetPadding,
        AppSpacing.sm,
        AppSpacing.sheetPadding,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetGrabHandle(),
          _Title(isEditing: state.isEditing, month: month),
          const SizedBox(height: AppSpacing.lg),
          AmountDisplay(label: state.amountLabel),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.errorMessage!,
              key: const Key('budget_form_error'),
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _CategoryField(
            state: state,
            editing: editing,
            onSelected: controller.selectCategory,
          ),
          const SizedBox(height: AppSpacing.lg),
          AmountKeypad(
            onDigit: controller.pressDigit,
            onBackspace: controller.pressBackspace,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: state.isEditing ? 'Salvar limite' : 'Definir limite',
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
          if (state.isEditing) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const Key('budget_form_remove'),
              label: 'Remover orçamento',
              variant: AppButtonVariant.ghost,
              onPressed: state.isSaving
                  ? null
                  : () async {
                      final removed = await controller.remove();
                      if (removed && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
            ),
          ],
        ],
      ),
    );
  }
}

/// Título mais a vigência do limite.
///
/// Dizer "a partir de julho" na própria folha evita a pergunta que o modelo de
/// vigência levanta: mudar o limite hoje não reescreve os meses anteriores.
class _Title extends StatelessWidget {
  const _Title({required this.isEditing, required this.month});

  final bool isEditing;
  final DateTime month;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        isEditing ? 'Editar orçamento' : 'Novo orçamento',
        style: context.texts.titleMedium,
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        'Limite mensal a partir de ${monthLabel(month)}',
        textAlign: TextAlign.center,
        style: context.texts.bodySmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
    ],
  );
}

/// Escolha da categoria orçada.
///
/// Ao criar, mostra só categorias **ainda sem limite no mês** — orçar a mesma
/// categoria duas vezes no mesmo mês não existe (a chave de negócio é única), e
/// esconder o caso impossível é melhor que explicá-lo num erro. Ao editar, a
/// categoria é a identidade do orçamento e não muda.
class _CategoryField extends ConsumerWidget {
  const _CategoryField({
    required this.state,
    required this.editing,
    required this.onSelected,
  });

  final BudgetFormState state;
  final Budget? editing;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesById = ref.watch(categoriesByIdProvider);

    if (editing != null) {
      final name = categoriesById[editing!.categoryId]?.name ?? 'Categoria';
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Categoria: ', style: context.texts.bodySmall),
          Text(name, style: context.texts.titleSmall),
        ],
      );
    }

    final all =
        ref.watch(categoriesProvider).asData?.value ?? const <Category>[];
    final alreadyBudgeted = {
      for (final usage in ref.watch(budgetUsageProvider)) usage.categoryId,
    };
    final available = [
      for (final category in all)
        if (!alreadyBudgeted.contains(category.id)) category,
    ];

    return CategoryPicker(
      categories: available,
      selectedId: state.categoryId,
      onSelected: onSelected,
      emptyMessage: all.isEmpty
          ? 'Sincronizando categorias…'
          : 'Todas as categorias já têm limite neste mês.',
    );
  }
}
