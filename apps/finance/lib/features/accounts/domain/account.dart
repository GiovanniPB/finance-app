import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'account.freezed.dart';

/// Natureza da conta (PRD §5.2).
///
/// O conjunto foi escolhido para o mapeamento com a Pluggy ser total, sem
/// caixa "não sei": `CHECKING_ACCOUNT`, `SAVINGS_ACCOUNT` e `CREDIT_CARD` são
/// os três subtipos que ela entrega (docs/pluggy-api-reference.md §7.3), e
/// [investment], [cash] e [other] cobrem o que só entra na mão.
enum AccountType {
  checking,
  savings,
  creditCard,
  investment,
  cash,
  other;

  static AccountType fromDb(String value) => switch (value) {
    'checking' => AccountType.checking,
    'savings' => AccountType.savings,
    'credit_card' => AccountType.creditCard,
    'investment' => AccountType.investment,
    'cash' => AccountType.cash,
    'other' => AccountType.other,
    _ => throw ArgumentError.value(value, 'account_type', 'Tipo inválido'),
  };

  String get db => this == AccountType.creditCard ? 'credit_card' : name;

  /// Se o saldo da conta é uma **dívida** em vez de dinheiro disponível.
  ///
  /// Cartão de crédito guarda a fatura: o número é o quanto se deve. É o mesmo
  /// desenho de `TransactionType.isOutflow` — a coluna é positiva e o tipo diz
  /// para que lado ela aponta.
  bool get isDebt => this == AccountType.creditCard;

  /// Rótulo em português, usado na lista e no formulário.
  String get label => switch (this) {
    AccountType.checking => 'Conta corrente',
    AccountType.savings => 'Poupança',
    AccountType.creditCard => 'Cartão de crédito',
    AccountType.investment => 'Investimento',
    AccountType.cash => 'Dinheiro',
    AccountType.other => 'Outra',
  };
}

/// Entidade de domínio: uma conta financeira do usuário.
///
/// ## Sinal do saldo
///
/// O banco guarda `current_balance_minor` **sempre positivo** e deriva a
/// direção de `account_type` — mesma convenção de `transactions` (ver o
/// cabeçalho da migration 20260727210000). No domínio, [currentBalance] é o
/// número como foi digitado e [signedBalance] é o valor com sinal, que é o que
/// soma corretamente entre contas.
///
/// ## Saldo é snapshot
///
/// [currentBalance] é "o que o banco dizia da última vez", não a soma dos
/// lançamentos. Lançamento manual cobre uma fração do extrato, então derivar
/// daria um número errado com cara de certo. Na Fase 1 a ingestão da Pluggy
/// passa a ser dona desta coluna nas contas de Open Finance (ADR 0005).
@freezed
abstract class Account with _$Account {
  const factory Account({
    required String id,
    required String ownerId,
    required String name,
    required AccountType type,
    required Money currentBalance,
    required bool isSavingsTarget,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// Nome da instituição (banco, corretora). Nulo em conta de dinheiro vivo.
    String? institution,

    /// Household ao qual a conta foi vinculada, tornando-a visível para os
    /// outros membros daquele espaço (ADR 0004). Nulo = só o dono vê.
    String? linkedSpaceId,
  }) = _Account;

  const Account._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  /// Datas são texto ISO-8601; o `id` é a PK implícita do PowerSync.
  factory Account.fromRow(Map<String, Object?> row) => Account(
    id: row['id']! as String,
    ownerId: row['owner_id']! as String,
    name: row['name']! as String,
    // Conta gravada antes desta coluna existir não tem tipo: `checking` é o
    // mesmo default da migration, então a leitura nunca quebra.
    type: AccountType.fromDb(row['account_type'] as String? ?? 'checking'),
    currentBalance: Money.fromMinor(
      row['current_balance_minor'] as int? ?? 0,
      currency: row['currency']! as String,
    ),
    isSavingsTarget: (row['is_savings_target'] as int? ?? 0) != 0,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    institution: row['institution'] as String?,
    linkedSpaceId: row['linked_space_id'] as String?,
  );

  /// Colunas para INSERT/UPDATE no banco local.
  ///
  /// Descarta o sinal do saldo: a coluna é positiva por constraint e o tipo
  /// carrega a direção.
  Map<String, Object?> toColumns() => {
    'id': id,
    'owner_id': ownerId,
    'linked_space_id': linkedSpaceId,
    'name': name,
    'account_type': type.db,
    'institution': institution,
    'currency': currentBalance.currency,
    'current_balance_minor': currentBalance.amountMinor.abs(),
    'is_savings_target': isSavingsTarget ? 1 : 0,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// Moeda da conta (ISO-4217). Vive no [currentBalance] para não haver duas
  /// fontes de verdade — mesma escolha de `Transaction.amount`.
  String get currency => currentBalance.currency;

  /// Saldo com sinal: negativo quando o número é dívida (fatura de cartão).
  /// É este o valor que soma corretamente entre contas de tipos diferentes.
  Money get signedBalance => type.isDebt
      ? Money.fromMinor(-currentBalance.amountMinor.abs(), currency: currency)
      : currentBalance.abs;

  /// Visível para os membros de um household, e não só para o dono.
  bool get isSharedWithHousehold => linkedSpaceId != null;
}
