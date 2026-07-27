import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'budget.freezed.dart';

/// Período de apuração do orçamento (RN-1.3).
enum BudgetPeriod {
  monthly,
  weekly;

  static BudgetPeriod fromDb(String value) => switch (value) {
    'monthly' => BudgetPeriod.monthly,
    'weekly' => BudgetPeriod.weekly,
    _ => throw ArgumentError.value(value, 'period', 'Período inválido'),
  };

  String get db => name;
}

/// Entidade de domínio: limite de gasto de uma categoria num período.
@freezed
abstract class Budget with _$Budget {
  const factory Budget({
    required String id,
    required String spaceId,
    required String categoryId,
    required Money limit,
    required BudgetPeriod period,
    required DateTime startsAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Budget;

  const Budget._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  factory Budget.fromRow(Map<String, Object?> row) => Budget(
    id: row['id']! as String,
    spaceId: row['space_id']! as String,
    categoryId: row['category_id']! as String,
    limit: Money.fromMinor(
      row['amount_minor']! as int,
      currency: row['currency']! as String,
    ),
    period: BudgetPeriod.fromDb(row['period']! as String),
    startsAt: DateTime.parse(row['starts_at']! as String),
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );

  /// Colunas para INSERT/UPDATE no banco local.
  ///
  /// `starts_at` é `date` no Postgres: grava só a parte da data.
  Map<String, Object?> toColumns() => {
    'id': id,
    'space_id': spaceId,
    'category_id': categoryId,
    'amount_minor': limit.amountMinor,
    'currency': limit.currency,
    'period': period.db,
    'starts_at': dateOnly(startsAt),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// `starts_at` no formato do banco (`date`, sem hora).
  ///
  /// Público porque é a chave de negócio do orçamento: a camada `data` compara
  /// por esta string para achar o orçamento do período. Delega para [isoDate]
  /// em `package:core`, a mesma necessidade de toda coluna `date`.
  static String dateOnly(DateTime value) => isoDate(value);
}

/// Orçamento cruzado com o gasto acumulado do período.
///
/// Não é entidade persistida: é o resultado de compor um [Budget] com as
/// transações do período. Os limiares seguem RN-1.3 (alerta em 80% e 100%).
@immutable
class BudgetUsage {
  const BudgetUsage({required this.budget, required this.spent});

  final Budget budget;

  /// Total gasto na categoria no período. Valor absoluto (positivo).
  final Money spent;

  String get categoryId => budget.categoryId;

  /// Fração do limite consumida. Pode passar de 1 quando estourado.
  double get ratio {
    if (budget.limit.amountMinor <= 0) return 0;
    return spent.amountMinor / budget.limit.amountMinor;
  }

  /// Percentual inteiro para exibição.
  int get percent => (ratio * 100).round();

  /// Passou do limite.
  bool get isOver => ratio > 1;

  /// Chegou na zona de atenção (≥ 80%) sem necessariamente estourar.
  bool get needsAttention => ratio >= 0.8;

  /// Quanto ainda cabe. Zero quando estourado (nunca negativo).
  Money get remaining {
    final left = budget.limit - spent;
    return left.isNegative ? Money.zero(currency: left.currency) : left;
  }
}
