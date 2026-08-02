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
    this.accountLabels = const {},
    this.onTapTransaction,
    super.key,
  });

  final List<TransactionDay> days;
  final Map<String, Category> categoriesById;

  /// Nome da conta por id. Vazio esconde a conta da linha — é o que
  /// `accountLabelsProvider` devolve quando há uma conta só.
  final Map<String, String> accountLabels;

  final void Function(Transaction)? onTapTransaction;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
    itemCount: days.length,
    itemBuilder: (context, index) => TransactionDaySection(
      day: days[index],
      categoriesById: categoriesById,
      accountLabels: accountLabels,
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
    this.accountLabels = const {},
    this.onTapTransaction,
    super.key,
  });

  final TransactionDay day;
  final Map<String, Category> categoriesById;
  final Map<String, String> accountLabels;
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
                  accountName: accountLabels[day.transactions[i].accountId],
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
  const _Row({
    required this.transaction,
    this.category,
    this.accountName,
    this.onTap,
  });

  final Transaction transaction;
  final Category? category;
  final String? accountName;
  final void Function(Transaction)? onTap;

  /// Rótulo que substitui a categoria em lançamento que não tem uma **por
  /// definição**.
  ///
  /// Poupança não tem categoria de propósito (atribuir uma faria o valor
  /// debitar um orçamento). Transferência também não: ela nasce da ingestão do
  /// Open Finance quando o dinheiro só troca de bolso — o caso que a produz é
  /// pagar a fatura do cartão. Sem este rótulo a linha ficaria com o ícone de
  /// "falta classificar" e leria como despesa comum, enquanto o resumo do mês a
  /// ignora: R$ 10 mil visíveis na lista e ausentes do total.
  static String? _typeLabel(TransactionType type) => switch (type) {
    TransactionType.savings => 'Poupança',
    TransactionType.transfer => 'Transferência',
    TransactionType.expense || TransactionType.income => null,
  };

  static String? _meta(
    String? categoryName,
    String? accountName, {
    required String? typeLabel,
    required bool isShared,
  }) {
    final parts = [
      if (typeLabel != null) typeLabel else ?categoryName,
      ?accountName,
      // Último, porque é o menos frequente e o menos procurado — mas presente,
      // porque sem ele a divisão só existiria dentro da folha de edição, e
      // ninguém abre lançamento por lançamento para saber quais dividiu.
      if (isShared) 'Dividida',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final categoryName = category?.name;
    final typeLabel = _typeLabel(transaction.type);
    final icon = transaction.isIncome
        ? CategoryIcons.income
        // Ícone próprio: o de "sem categoria" leria como lançamento que falta
        // classificar, e estes não faltam — não têm categoria por definição.
        : switch (transaction.type) {
            TransactionType.savings => Icons.savings_outlined,
            TransactionType.transfer => Icons.swap_horiz,
            _ =>
              category == null
                  ? CategoryIcons.uncategorized
                  : CategoryIcons.resolve(category!.iconKey),
          };

    final described = transaction.description?.trim();
    final hasDescription = described != null && described.isNotEmpty;

    return TransactionTile(
      description: hasDescription ? described : categoryName ?? 'Sem descrição',
      amount: transaction.amount,
      icon: icon,
      // Receita usa o swatch da marca; despesa, a matiz da categoria.
      categoryId: transaction.isIncome ? null : transaction.categoryId,
      categoryColorIndex: transaction.isIncome ? null : category?.colorIndex,
      // Sem descrição, o título já é o nome da categoria: repeti-lo embaixo
      // ("Alimentação / Alimentação") gasta uma linha para não dizer nada.
      // A conta entra ao lado dela, e só quando há mais de uma para distinguir
      // (ver `accountLabelsProvider`).
      meta: _meta(
        hasDescription ? categoryName : null,
        accountName,
        typeLabel: typeLabel,
        isShared: transaction.isShared,
      ),
      isIncome: transaction.isIncome,
      onTap: onTap == null ? null : () => onTap!(transaction),
    );
  }
}

// `formatDayLabel` vive em `package:core` desde que a feature de contas também
// passou a precisar dele (data do saldo). Ficava aqui.
