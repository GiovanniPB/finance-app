import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/domain/category.dart';
import '../../categories/presentation/categories_providers.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/budget.dart';
import 'budget_form_sheet.dart';
import 'budgets_providers.dart';

/// Orçamentos do mês em foco: quanto foi definido e quanto já foi consumido.
///
/// A ordem é do provider — estourado primeiro, depois perto do limite. A tela
/// não reordena: o que exige ação fica no alto por construção.
class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(focusedMonthProvider);
    final usage = ref.watch(budgetUsageProvider);
    final categoriesById = ref.watch(categoriesByIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orçamento'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.screenGutter,
              bottom: AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                monthLabel(month),
                style: context.texts.labelSmall,
              ),
            ),
          ),
        ),
      ),
      body: usage.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: AppEmptyState(
                icon: Icons.pie_chart_outline,
                title: 'Nenhum limite em ${monthLabel(month)}',
                message:
                    'Defina um limite por categoria para acompanhar quanto '
                    'ainda cabe no mês.',
                actionLabel: 'Definir limite',
                onAction: () => BudgetFormSheet.show(context),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.lg,
                AppSpacing.screenGutter,
                AppSpacing.xxxl,
              ),
              itemCount: usage.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) => BudgetUsageCard(
                usage: usage[index],
                category: categoriesById[usage[index].categoryId],
                onTap: () => BudgetFormSheet.show(
                  context,
                  editing: usage[index].budget,
                ),
              ),
            ),
      floatingActionButton: usage.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('new_budget'),
              onPressed: () => BudgetFormSheet.show(context),
              icon: const Icon(Icons.add),
              label: const Text('Novo limite'),
            ),
    );
  }
}

/// Uma linha da lista: progresso do limite mais o quanto ainda cabe.
///
/// O restante em texto, e não só a barra, porque "faltam R$ 358,90" é a
/// resposta que a pessoa procura — o percentual é o contexto dela, não o
/// contrário.
class BudgetUsageCard extends StatelessWidget {
  const BudgetUsageCard({
    required this.usage,
    required this.category,
    this.onTap,
    super.key,
  });

  final BudgetUsage usage;
  final Category? category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: context.colors.surfaceContainerLow,
      borderRadius: AppRadii.brXl,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.brXl,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadii.brXl,
            border: Border.all(color: tokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BudgetProgress(
                category: category?.name ?? 'Sem categoria',
                spent: usage.spent,
                limit: usage.budget.limit,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                usage.isOver
                    ? 'Estourou em '
                          '${(usage.spent - usage.budget.limit).format()}'
                    : 'Faltam ${usage.remaining.format()}',
                style: context.texts.bodySmall?.copyWith(
                  color: usage.isOver ? tokens.moneyOver : tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
