import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../budgets/domain/budget.dart';
import '../../budgets/presentation/budgets_providers.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/categories_providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/quick_entry_sheet.dart';
import '../../transactions/presentation/transaction_list.dart';
import '../../transactions/presentation/transactions_page.dart';
import '../../transactions/presentation/transactions_providers.dart';

/// Home do espaço ativo.
///
/// O **momento alto** é o saldo do mês, em 40px mono. Todo o resto fica
/// quieto — é assim que a hierarquia nasce de contraste de escala, não de
/// decoração.
class SpaceHomePage extends ConsumerWidget {
  const SpaceHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(activeSpaceProvider);
    if (space == null) return const _WaitingSync();

    final month = ref.watch(focusedMonthProvider);
    final summary = ref.watch(monthSummaryProvider);
    final transactions =
        ref.watch(monthTransactionsProvider).asData?.value ??
        const <Transaction>[];
    final usage = ref.watch(budgetUsageProvider);
    final categoriesById = ref.watch(categoriesByIdProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        _Header(spaceName: space.name),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.xxl,
            AppSpacing.screenGutter,
            AppSpacing.xxxl,
          ),
          child: BalanceHeader(
            label: 'Saldo de ${monthLabel(month)}',
            amount: summary.balance,
            caption: _entriesCaption(summary.income, summary.outflow),
          ),
        ),
        if (usage.isNotEmpty) ...[
          const _SectionTitle(title: 'Orçamento do mês'),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            child: _BudgetCard(usage: usage, categoriesById: categoriesById),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
        if (transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: AppEmptyState(
              icon: Icons.add,
              title: 'Nenhum gasto em ${monthLabel(month)}',
              message: 'Registre o primeiro em menos de 30 segundos.',
              actionLabel: 'Registrar gasto',
              onAction: () => QuickEntrySheet.show(context),
            ),
          )
        else ...[
          _SectionTitle(
            title: 'Atividade recente',
            actionLabel: 'Ver tudo',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TransactionsPage(),
              ),
            ),
          ),
          _RecentActivity(
            transactions: transactions.take(3).toList(),
            categoriesById: categoriesById,
          ),
        ],
      ],
    );
  }

  /// Legenda do saldo: entradas e saídas em texto, sem competir com o valor.
  String _entriesCaption(Money income, Money outflow) =>
      'Entradas ${income.format()} · Saídas ${outflow.format()}';
}

class _Header extends StatelessWidget {
  const _Header({required this.spaceName});

  final String spaceName;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      AppSpacing.sm,
      AppSpacing.screenGutter,
      0,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Espaço ativo',
                style: context.texts.labelSmall,
              ),
              Text(
                spaceName,
                key: const Key('active_space_name'),
                style: context.texts.titleMedium,
              ),
            ],
          ),
        ),
        const _MonthStepper(),
      ],
    ),
  );
}

class _MonthStepper extends ConsumerWidget {
  const _MonthStepper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(focusedMonthProvider.notifier);
    return Row(
      children: [
        IconButton(
          key: const Key('previous_month'),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mês anterior',
          onPressed: notifier.previous,
        ),
        IconButton(
          key: const Key('next_month'),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mês seguinte',
          onPressed: notifier.next,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        0,
        AppSpacing.screenGutter,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.texts.titleSmall)),
          if (label != null)
            AppButton(
              label: label,
              variant: AppButtonVariant.ghost,
              expand: false,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.usage, required this.categoriesById});

  final List<BudgetUsage> usage;
  final Map<String, Category> categoriesById;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: AppRadii.brXl,
      border: Border.all(color: context.tokens.hairline),
      boxShadow: context.tokens.cardShadow,
    ),
    child: Column(
      children: [
        for (var i = 0; i < usage.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          BudgetProgress(
            category:
                categoriesById[usage[i].categoryId]?.name ?? 'Sem categoria',
            spent: usage[i].spent,
            limit: usage[i].budget.limit,
          ),
        ],
      ],
    ),
  );
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({
    required this.transactions,
    required this.categoriesById,
  });

  final List<Transaction> transactions;
  final Map<String, Category> categoriesById;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final day in TransactionDay.groupByDay(transactions))
        TransactionDaySection(day: day, categoriesById: categoriesById),
    ],
  );
}

class _WaitingSync extends StatelessWidget {
  const _WaitingSync();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: AppSpacing.lg),
        Text('Sincronizando seus dados…'),
      ],
    ),
  );
}

/// Nome do mês em pt-BR, com o ano quando não é o corrente.
String monthLabel(DateTime month, {DateTime? today}) {
  const names = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];
  final name = names[month.month - 1];
  final currentYear = (today ?? DateTime.now()).year;
  return month.year == currentYear ? name : '$name de ${month.year}';
}
