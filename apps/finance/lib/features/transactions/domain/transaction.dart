import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transaction.freezed.dart';

/// Natureza da transação (PRD §5.2).
enum TransactionType {
  expense,
  income,
  transfer,
  savings;

  static TransactionType fromDb(String value) => switch (value) {
    'expense' => TransactionType.expense,
    'income' => TransactionType.income,
    'transfer' => TransactionType.transfer,
    'savings' => TransactionType.savings,
    _ => throw ArgumentError.value(value, 'type', 'Tipo inválido'),
  };

  String get db => name;

  /// Se o valor **sai** do saldo disponível.
  ///
  /// `savings` conta como saída porque o dinheiro deixa o saldo gastável mesmo
  /// sem ser despesa. `transfer` **não** conta em nenhum dos dois lados: o
  /// dinheiro só trocou de bolso. Quem o produz é a ingestão do Open Finance,
  /// no crédito de cartão (pagar a fatura); a UI não o oferece, porque escolher
  /// origem e destino à mão é desenho que ainda não existe.
  bool get isOutflow =>
      this == TransactionType.expense || this == TransactionType.savings;
}

/// Origem do registro (RN-1.1).
enum TransactionSource {
  manual,
  openFinance;

  static TransactionSource fromDb(String value) => switch (value) {
    'manual' => TransactionSource.manual,
    'open_finance' => TransactionSource.openFinance,
    _ => throw ArgumentError.value(value, 'source', 'Origem inválida'),
  };

  String get db =>
      this == TransactionSource.openFinance ? 'open_finance' : 'manual';
}

/// Entidade de domínio: uma transação dentro de um espaço.
///
/// ## Sinal do valor
///
/// O banco guarda `amount_minor` **sempre positivo** e deriva a direção de
/// `type` — guardar sinal na coluna permitiria "receita negativa", dado
/// contraditório que nenhuma constraint pegaria. No domínio o oposto é mais
/// útil: [amount] é um [Money] **com sinal** (negativo para saída), o que deixa
/// somas e saldos serem aritmética direta. A conversão acontece na fronteira,
/// em [Transaction.fromRow] e [toColumns].
///
/// ## Quem pagou nunca é nulo aqui
///
/// A coluna `paid_by` é nulável e nulo significa "quem lançou" — no Postgres um
/// trigger resolve, e na linha local (que não tem trigger) o `coalesce`
/// acontece em [Transaction.fromRow]. No domínio [paidBy] é sempre um id: quem
/// consome não deveria repetir a regra, e "não se sabe quem pagou" não é um
/// estado que exista para quem lê.
@freezed
abstract class Transaction with _$Transaction {
  const factory Transaction({
    required String id,
    required String spaceId,
    required String createdBy,

    /// Quem pagou. Igual a [createdBy] quando ninguém escolheu outra pessoa.
    required String paidBy,
    required TransactionType type,
    required Money amount,
    required DateTime occurredAt,
    required TransactionSource source,
    required bool isShared,
    required bool aiCategorized,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? accountId,
    String? categoryId,
    String? description,
    String? recurrenceId,
  }) = _Transaction;

  const Transaction._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  ///
  /// Aplica o sinal conforme o tipo: saída vira valor negativo no domínio.
  factory Transaction.fromRow(Map<String, Object?> row) {
    final type = TransactionType.fromDb(row['type']! as String);
    final minor = row['amount_minor']! as int;
    final currency = row['currency']! as String;
    final createdBy = row['created_by']! as String;

    return Transaction(
      id: row['id']! as String,
      spaceId: row['space_id']! as String,
      createdBy: createdBy,
      // Nulo é o caso normal de toda linha anterior à migration 20260801224605,
      // e o de qualquer linha criada offline antes do round-trip.
      paidBy: row['paid_by'] as String? ?? createdBy,
      type: type,
      amount: Money.fromMinor(
        type.isOutflow ? -minor.abs() : minor.abs(),
        currency: currency,
      ),
      occurredAt: DateTime.parse(row['occurred_at']! as String),
      source: TransactionSource.fromDb(row['source']! as String),
      isShared: (row['is_shared'] as int? ?? 0) != 0,
      aiCategorized: (row['ai_categorized'] as int? ?? 0) != 0,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      accountId: row['account_id'] as String?,
      categoryId: row['category_id'] as String?,
      description: row['description'] as String?,
      recurrenceId: row['recurrence_id'] as String?,
    );
  }

  /// Colunas para INSERT/UPDATE no banco local.
  ///
  /// Descarta o sinal: a coluna é positiva por constraint e o tipo carrega a
  /// direção.
  Map<String, Object?> toColumns() => {
    'id': id,
    'space_id': spaceId,
    'account_id': accountId,
    'created_by': createdBy,
    'paid_by': paidBy,
    'type': type.db,
    'amount_minor': amount.amountMinor.abs(),
    'currency': amount.currency,
    'category_id': categoryId,
    'description': description,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'source': source.db,
    'is_shared': isShared ? 1 : 0,
    'ai_categorized': aiCategorized ? 1 : 0,
    'recurrence_id': recurrenceId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// Receita — usado pela UI para escolher cor e sinal do valor.
  bool get isIncome => type == TransactionType.income;

  /// Alguém pagou por quem lançou — o caso que torna `paid_by` necessária.
  bool get paidBySomeoneElse => paidBy != createdBy;

  /// Veio do Open Finance em vez de digitada.
  bool get isAutomatic => source == TransactionSource.openFinance;
}
