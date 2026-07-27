import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../../categories/domain/category.dart';
import '../../categories/presentation/category_icons.dart';
import '../domain/transaction.dart';

/// Um dia de transações, com o total do dia.
@immutable
class TransactionDay {
  const TransactionDay({required this.date, required this.transactions});

  final DateTime date;
  final List<Transaction> transactions;

  /// Soma com sinal das transações do dia.
  Money get total => transactions.fold(
    const Money.zero(),
    (sum, transaction) => sum + transaction.amount,
  );

  /// Agrupa por dia, preservando a ordem (mais recente primeiro) que veio do
  /// repositório.
  static List<TransactionDay> groupByDay(List<Transaction> transactions) {
    final buckets = <DateTime, List<Transaction>>{};
    for (final transaction in transactions) {
      final local = transaction.occurredAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      (buckets[day] ??= []).add(transaction);
    }

    final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        TransactionDay(date: day, transactions: buckets[day]!),
    ];
  }
}

/// Lista de transações agrupada por dia — a superfície mais densa do app.
class TransactionList extends StatelessWidget {
  const TransactionList({
    required this.days,
    required this.categoriesById,
    this.onTapTransaction,
    super.key,
  });

  final List<TransactionDay> days;
  final Map<String, Category> categoriesById;
  final void Function(Transaction)? onTapTransaction;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
    itemCount: days.length,
    itemBuilder: (context, index) => TransactionDaySection(
      day: days[index],
      categoriesById: categoriesById,
      onTapTransaction: onTapTransaction,
    ),
  );
}

/// Um dia da lista: cabeçalho com data e total, e as linhas do dia.
///
/// Público porque a home reaproveita a seção sozinha para "atividade recente",
/// sem a `ListView` em volta.
class TransactionDaySection extends StatelessWidget {
  const TransactionDaySection({
    required this.day,
    required this.categoriesById,
    this.onTapTransaction,
    super.key,
  });

  final TransactionDay day;
  final Map<String, Category> categoriesById;
  final void Function(Transaction)? onTapTransaction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.lg,
            AppSpacing.screenGutter,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  formatDayLabel(day.date),
                  style: context.texts.labelSmall,
                ),
              ),
              MoneyText(
                day.total,
                size: MoneySize.small,
                tone: day.total.isNegative
                    ? MoneyTone.neutral
                    : MoneyTone.positive,
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            border: Border(
              top: BorderSide(color: tokens.hairline),
              bottom: BorderSide(color: tokens.hairline),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < day.transactions.length; i++) ...[
                if (i > 0) Divider(height: 1, color: tokens.hairline),
                _Row(
                  transaction: day.transactions[i],
                  category: categoriesById[day.transactions[i].categoryId],
                  onTap: onTapTransaction,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.transaction, this.category, this.onTap});

  final Transaction transaction;
  final Category? category;
  final void Function(Transaction)? onTap;

  @override
  Widget build(BuildContext context) {
    final categoryName = category?.name;
    final icon = transaction.isIncome
        ? CategoryIcons.income
        : category == null
        ? CategoryIcons.uncategorized
        : CategoryIcons.resolve(category!.iconKey);

    return TransactionTile(
      description: transaction.description?.trim().isNotEmpty ?? false
          ? transaction.description!
          : categoryName ?? 'Sem descrição',
      amount: transaction.amount,
      icon: icon,
      // Receita usa o swatch da marca; despesa, a matiz da categoria.
      categoryId: transaction.isIncome ? null : transaction.categoryId,
      meta: categoryName,
      isIncome: transaction.isIncome,
      onTap: onTap == null ? null : () => onTap!(transaction),
    );
  }
}

/// Rótulo do dia em pt-BR, com "Hoje" e "Ontem" no lugar da data.
///
/// [today] existe para o teste não depender do relógio.
String formatDayLabel(DateTime date, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final reference = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final difference = reference.difference(target).inDays;

  if (difference == 0) return 'Hoje';
  if (difference == 1) return 'Ontem';

  const months = [
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
  return '${target.day} de ${months[target.month - 1]}';
}
