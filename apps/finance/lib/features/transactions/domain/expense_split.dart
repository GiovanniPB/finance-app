import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'expense_split.freezed.dart';

/// Quanto uma pessoa deve de uma despesa dividida (RN-2.1).
///
/// ─────────────────────────────────────────────────────────────────────────
/// A PARTE É POSITIVA, MESMO SENDO DE UMA DESPESA
///
/// `Transaction.amount` de despesa é negativo — o sinal carrega a direção. Aqui
/// não: a parte responde "quanto desta despesa é seu", e a resposta é uma
/// quantia. Somar partes com sinal daria um total negativo que ninguém pediu, e
/// a tela que as exibe já está sob o rótulo "Dividido entre".
///
/// Zero é valor legítimo: R$ 0,01 entre três pessoas dá uma parte de um centavo
/// e duas de zero. Omitir as duas pessoas mentiria sobre quem participou.
@freezed
abstract class ExpenseSplit with _$ExpenseSplit {
  const factory ExpenseSplit({
    required String id,
    required String transactionId,
    required String spaceId,
    required String userId,
    required Money amount,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _ExpenseSplit;

  const ExpenseSplit._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  factory ExpenseSplit.fromRow(Map<String, Object?> row) => ExpenseSplit(
    id: row['id']! as String,
    transactionId: row['transaction_id']! as String,
    spaceId: row['space_id']! as String,
    userId: row['user_id']! as String,
    amount: Money.fromMinor(
      (row['amount_minor']! as int).abs(),
      currency: row['currency']! as String,
    ),
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );

  /// Colunas para INSERT no banco local.
  ///
  /// `space_id` e `currency` vão preenchidos para a linha ser utilizável antes
  /// do round-trip, mas no Postgres o trigger
  /// `expense_splits_inherit_from_transaction` os reescreve a partir do
  /// lançamento — que é quem manda.
  Map<String, Object?> toColumns() => {
    'id': id,
    'transaction_id': transactionId,
    'space_id': spaceId,
    'user_id': userId,
    'amount_minor': amount.amountMinor.abs(),
    'currency': amount.currency,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

/// Soma das partes, para a tela poder provar que o rateio fecha o total.
extension ExpenseSplitTotal on List<ExpenseSplit> {
  /// `null` quando a lista é vazia — não há moeda para somar em.
  Money? get total => isEmpty
      ? null
      : skip(1).fold<Money>(first.amount, (sum, split) => sum + split.amount);
}
