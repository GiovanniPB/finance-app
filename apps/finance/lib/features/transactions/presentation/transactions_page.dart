import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/presentation/accounts_providers.dart';
import '../../categories/presentation/categories_providers.dart';
import '../domain/transaction.dart';
import 'quick_entry_sheet.dart';
import 'transaction_edit_sheet.dart';
import 'transaction_list.dart';
import 'transactions_providers.dart';

/// Lista completa das transações do mês em foco (PRD §11.2).
///
/// A home mostra só as mais recentes; esta tela é o mês inteiro, com troca de
/// mês no cabeçalho e o resumo de entradas/saídas no topo.
class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(focusedMonthProvider);
    final summary = ref.watch(monthSummaryProvider);
    final transactions =
        ref.watch(monthTransactionsProvider).asData?.value ??
        const <Transaction>[];
    final categoriesById = ref.watch(categoriesByIdProvider);
    final notifier = ref.read(focusedMonthProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(monthLabel(month)),
        actions: [
          IconButton(
            key: const Key('list_previous_month'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Mês anterior',
            onPressed: notifier.previous,
          ),
          IconButton(
            key: const Key('list_next_month'),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Mês seguinte',
            onPressed: notifier.next,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: _SummaryStrip(
              income: summary.income,
              outflow: summary.outflow,
            ),
          ),
          Expanded(
            child: transactions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenGutter),
                    child: AppEmptyState(
                      icon: Icons.add,
                      title: 'Nenhum lançamento em ${monthLabel(month)}',
                      message: 'Registre o primeiro em menos de 30 segundos.',
                      actionLabel: 'Registrar gasto',
                      onAction: () => QuickEntrySheet.show(context),
                    ),
                  )
                : TransactionList(
                    days: TransactionDay.groupByDay(transactions),
                    categoriesById: categoriesById,
                    accountLabels: ref.watch(accountLabelsProvider),
                    onTapTransaction: (transaction) =>
                        TransactionEditSheet.show(context, transaction),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Entradas e saídas do mês, lado a lado. Quieto de propósito — o conteúdo da
/// tela é a lista, não o resumo.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.income, required this.outflow});

  final Money income;
  final Money outflow;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppRadii.brXl,
        border: Border.all(color: tokens.hairline),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Cell(
              label: 'Entradas',
              amount: income,
              tone: MoneyTone.positive,
            ),
          ),
          Container(width: 1, height: 52, color: tokens.hairline),
          Expanded(
            child: _Cell(
              label: 'Saídas',
              amount: outflow,
              tone: MoneyTone.neutral,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.amount,
    required this.tone,
  });

  final String label;
  final Money amount;
  final MoneyTone tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.texts.labelMedium),
        const SizedBox(height: 3),
        MoneyText(amount, size: MoneySize.large, tone: tone),
      ],
    ),
  );
}
