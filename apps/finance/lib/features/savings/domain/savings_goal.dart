import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'savings_goal.freezed.dart';

/// Tipo de meta de poupança (PRD RN-3.1).
///
/// O PRD lista um quarto tipo, `recurring_challenge` (52 semanas, no-spend),
/// que **não existe aqui nem no banco**: mede hábito em vez de valor acumulado,
/// precisa de uma tela de progresso diferente e se sobrepõe ao conceito de
/// `challenges` da Fase 3. Entra quando esse conceito existir.
enum SavingsGoalType {
  /// Valor-alvo, com prazo opcional. Ex.: R$ 8.000 até março.
  objective,

  /// O mesmo valor todo mês. Ex.: R$ 500 por mês.
  fixedAmount,

  /// Uma fatia da renda do mês. Ex.: 20% do que entrar.
  percentageIncome;

  static SavingsGoalType fromDb(String value) => switch (value) {
    'objective' => SavingsGoalType.objective,
    'fixed_amount' => SavingsGoalType.fixedAmount,
    'percentage_income' => SavingsGoalType.percentageIncome,
    _ => throw ArgumentError.value(value, 'goal_type', 'Tipo inválido'),
  };

  String get db => switch (this) {
    SavingsGoalType.objective => 'objective',
    SavingsGoalType.fixedAmount => 'fixed_amount',
    SavingsGoalType.percentageIncome => 'percentage_income',
  };

  /// Se o alvo se renova a cada mês.
  ///
  /// É a diferença que mais aparece na tela: meta por objetivo acumula para
  /// sempre ("R$ 3.240 de R$ 8.000"), enquanto as mensais recomeçam ("R$ 500 de
  /// R$ 500 · julho"). Sem esta distinção o progresso somaria a vida toda
  /// contra um alvo de um mês, e toda mensal pareceria concluída no 2º mês.
  bool get isMonthly => this != SavingsGoalType.objective;

  String get label => switch (this) {
    SavingsGoalType.objective => 'Por objetivo',
    SavingsGoalType.fixedAmount => 'Valor fixo mensal',
    SavingsGoalType.percentageIncome => 'Percentual da renda',
  };

  /// Uma linha explicando o tipo, para o seletor do formulário.
  String get description => switch (this) {
    SavingsGoalType.objective =>
      r'Um valor e um prazo. Ex.: R$ 8.000 até '
          'março.',
    SavingsGoalType.fixedAmount =>
      r'O mesmo valor todo mês. Ex.: R$ 500 por '
          'mês.',
    SavingsGoalType.percentageIncome =>
      'Uma fatia do que entrar. Ex.: 20% da renda do mês.',
  };
}

/// Situação da meta (PRD §5.2).
enum SavingsGoalStatus {
  active,
  completed,
  paused;

  static SavingsGoalStatus fromDb(String value) => switch (value) {
    'active' => SavingsGoalStatus.active,
    'completed' => SavingsGoalStatus.completed,
    'paused' => SavingsGoalStatus.paused,
    _ => throw ArgumentError.value(value, 'status', 'Situação inválida'),
  };

  String get db => name;
}

/// Entidade de domínio: uma meta de poupança de um espaço.
///
/// ## Não há valor acumulado aqui
///
/// O PRD §5.2 lista `current_amount` como coluna, mas a RN-3.3 a define como "a
/// soma das contribuições confirmadas" — uma agregação, não um fato. Guardá-la
/// desincronizaria offline (ver o cabeçalho da migration 20260727235500). O
/// acumulado é `GoalProgress`, calculado a partir das contribuições.
///
/// ## Cada tipo usa colunas diferentes
///
/// [targetAmountMinor], [targetDate] e [percentage] são nulos ou não conforme
/// [type], e o banco tem um check de forma que recusa combinação sem sentido.
/// No Dart, [targetAmount] e [isMonthly] resolvem isso no ponto de leitura.
@freezed
abstract class SavingsGoal with _$SavingsGoal {
  const factory SavingsGoal({
    required String id,
    required String spaceId,
    required String createdBy,
    required SavingsGoalType type,
    required String name,
    required String currency,
    required SavingsGoalStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// Valor-alvo ([SavingsGoalType.objective]) ou valor por mês
    /// ([SavingsGoalType.fixedAmount]), em unidades mínimas. Nulo em meta
    /// percentual, onde o alvo é derivado da renda.
    ///
    /// Guardado como inteiro em vez de `Money?` porque a moeda existe mesmo
    /// quando o valor não: dois campos independentes poderiam divergir, e este
    /// não pode.
    int? targetAmountMinor,

    /// Prazo. **Opcional mesmo em meta por objetivo**: uma reserva de
    /// emergência legitimamente não tem data, e sem prazo não existe ritmo a
    /// comparar — a UI simplesmente não desenha a marca de ritmo.
    DateTime? targetDate,

    /// Fatia da renda em pontos percentuais inteiros (1–100).
    int? percentage,

    /// Conta onde o dinheiro é guardado. Nula quando a meta existe antes de
    /// haver conta cadastrada.
    String? linkedAccountId,
  }) = _SavingsGoal;

  const SavingsGoal._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  factory SavingsGoal.fromRow(Map<String, Object?> row) => SavingsGoal(
    id: row['id']! as String,
    spaceId: row['space_id']! as String,
    createdBy: row['created_by']! as String,
    type: SavingsGoalType.fromDb(row['goal_type']! as String),
    name: row['name']! as String,
    currency: row['currency'] as String? ?? Money.brl,
    status: SavingsGoalStatus.fromDb(row['status'] as String? ?? 'active'),
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    targetAmountMinor: row['target_amount_minor'] as int?,
    targetDate: switch (row['target_date']) {
      final String date when date.isNotEmpty => DateTime.parse(date),
      _ => null,
    },
    percentage: row['percentage'] as int?,
    linkedAccountId: row['linked_account_id'] as String?,
  );

  /// Colunas para INSERT/UPDATE no banco local.
  ///
  /// `target_date` é `date` no Postgres: grava só a parte da data (ver
  /// [isoDate]).
  Map<String, Object?> toColumns() => {
    'id': id,
    'space_id': spaceId,
    'created_by': createdBy,
    'goal_type': type.db,
    'name': name,
    'target_amount_minor': targetAmountMinor,
    'currency': currency,
    'target_date': targetDate == null ? null : isoDate(targetDate!),
    'percentage': percentage,
    'linked_account_id': linkedAccountId,
    'status': status.db,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// Valor-alvo como [Money], quando o tipo tem um. Nulo em meta percentual.
  Money? get targetAmount => targetAmountMinor == null
      ? null
      : Money.fromMinor(targetAmountMinor!, currency: currency);

  /// Se o alvo se renova a cada mês (atalho para [SavingsGoalType.isMonthly]).
  bool get isMonthly => type.isMonthly;

  /// Se há ritmo a comparar: só meta com prazo tem "onde eu deveria estar".
  bool get hasDeadline => targetDate != null;
}
