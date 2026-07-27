import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/savings_contribution.dart';
import '../domain/savings_goal.dart';
import '../domain/savings_repository.dart';

/// Statements de poupança, em constantes para o teste de guarda rodá-las contra
/// views iguais às que o PowerSync cria.
///
/// As tabelas locais do PowerSync são **views com triggers `INSTEAD OF`**, e o
/// SQLite recusa construções que uma tabela aceitaria — foi assim que o UPSERT
/// de orçamento passou meses quebrado com o teste verde, porque mock de conexão
/// compara o *texto* do SQL e não sabe distinguir SQL válido de SQL recusado.
abstract final class SavingsSql {
  static const watchGoals =
      'SELECT * FROM savings_goals WHERE space_id = ? '
      'ORDER BY created_at DESC';

  static const watchContributions =
      'SELECT * FROM savings_contributions WHERE space_id = ? '
      'ORDER BY contributed_at DESC';

  static const insertGoal =
      'INSERT INTO savings_goals (id, space_id, created_by, goal_type, name, '
      'target_amount_minor, currency, target_date, percentage, '
      'linked_account_id, status, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  /// `space_id`, `created_by`, `goal_type` e `created_at` ficam de fora: são a
  /// identidade da linha, não dado editável. Trocar o tipo de uma meta mudaria
  /// o significado do histórico de contribuições dela.
  static const updateGoal =
      'UPDATE savings_goals SET name = ?, target_amount_minor = ?, '
      'currency = ?, target_date = ?, percentage = ?, linked_account_id = ?, '
      'status = ?, updated_at = ? WHERE id = ?';

  static const deleteGoal = 'DELETE FROM savings_goals WHERE id = ?';

  static const deleteContributionsOfGoal =
      'DELETE FROM savings_contributions WHERE goal_id = ?';

  static const insertContribution =
      'INSERT INTO savings_contributions (id, goal_id, space_id, created_by, '
      'amount_minor, currency, detected_via, confirmed, contributed_at, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  /// Só a confirmação muda: valor, data e origem são do evento, não do usuário.
  static const confirmContribution =
      'UPDATE savings_contributions SET confirmed = 1, updated_at = ? '
      'WHERE id = ?';

  static const deleteContribution =
      'DELETE FROM savings_contributions WHERE id = ?';

  /// Ordem dos parâmetros do [insertGoal], a partir de `toColumns()`.
  static List<Object?> insertGoalParams(Map<String, Object?> cols) => [
    cols['id'],
    cols['space_id'],
    cols['created_by'],
    cols['goal_type'],
    cols['name'],
    cols['target_amount_minor'],
    cols['currency'],
    cols['target_date'],
    cols['percentage'],
    cols['linked_account_id'],
    cols['status'],
    cols['created_at'],
    cols['updated_at'],
  ];

  /// Ordem dos parâmetros do [updateGoal], a partir de `toColumns()`.
  static List<Object?> updateGoalParams(Map<String, Object?> cols) => [
    cols['name'],
    cols['target_amount_minor'],
    cols['currency'],
    cols['target_date'],
    cols['percentage'],
    cols['linked_account_id'],
    cols['status'],
    cols['updated_at'],
    cols['id'],
  ];

  /// Ordem dos parâmetros do [insertContribution], a partir de `toColumns()`.
  static List<Object?> insertContributionParams(Map<String, Object?> cols) => [
    cols['id'],
    cols['goal_id'],
    cols['space_id'],
    cols['created_by'],
    cols['amount_minor'],
    cols['currency'],
    cols['detected_via'],
    cols['confirmed'],
    cols['contributed_at'],
    cols['created_at'],
    cols['updated_at'],
  ];
}

/// Implementação sobre o PowerSync (SQL bruto). Leituras via `watch`
/// (reativas), escritas via `execute` (persistem local e entram na fila de
/// upload). Depende de [SqliteConnection] para permitir teste com mocks.
class SavingsRepositoryImpl implements SavingsRepository {
  SavingsRepositoryImpl({
    required this.db,
    required this.supabase,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('SavingsRepository');

  final SqliteConnection db;
  final SupabaseClient supabase;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  @override
  Stream<List<SavingsGoal>> watchGoals(String spaceId) => db
      .watch(SavingsSql.watchGoals, parameters: [spaceId])
      .map((results) => results.map(SavingsGoal.fromRow).toList());

  @override
  Stream<List<SavingsContribution>> watchContributions(String spaceId) => db
      .watch(SavingsSql.watchContributions, parameters: [spaceId])
      .map((results) => results.map(SavingsContribution.fromRow).toList());

  @override
  Future<Result<SavingsGoal, Failure>> createGoal({
    required String spaceId,
    required SavingsGoalType type,
    required String name,
    Money? targetAmount,
    DateTime? targetDate,
    int? percentage,
    String? linkedAccountId,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(AuthFailure('Nenhuma sessão ativa para criar meta.'));
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return const Err(ValidationFailure('Dê um nome para a meta.'));
    }

    final shape = _validateShape(
      type: type,
      targetAmount: targetAmount,
      percentage: percentage,
    );
    if (shape != null) return Err(shape);

    final timestamp = _now();
    final goal = SavingsGoal(
      id: _genId(),
      spaceId: spaceId,
      createdBy: userId,
      type: type,
      name: trimmedName,
      currency: targetAmount?.currency ?? Money.brl,
      status: SavingsGoalStatus.active,
      createdAt: timestamp,
      updatedAt: timestamp,
      // O banco tem um check de forma por tipo; zerar o que não pertence ao
      // tipo aqui evita que um campo deixado para trás na UI derrube a escrita.
      targetAmountMinor: type == SavingsGoalType.percentageIncome
          ? null
          : targetAmount?.amountMinor.abs(),
      targetDate: type == SavingsGoalType.objective ? targetDate : null,
      percentage: type == SavingsGoalType.percentageIncome ? percentage : null,
      linkedAccountId: linkedAccountId,
    );

    try {
      await db.execute(
        SavingsSql.insertGoal,
        SavingsSql.insertGoalParams(goal.toColumns()),
      );
      return Ok(goal);
    } on Exception catch (e, st) {
      _log.severe('Falha ao criar meta', e, st);
      return Err(DatabaseFailure('Não foi possível criar a meta.', cause: e));
    }
  }

  @override
  Future<Result<SavingsGoal, Failure>> updateGoal(SavingsGoal goal) async {
    final trimmedName = goal.name.trim();
    if (trimmedName.isEmpty) {
      return const Err(ValidationFailure('Dê um nome para a meta.'));
    }

    final shape = _validateShape(
      type: goal.type,
      targetAmount: goal.targetAmount,
      percentage: goal.percentage,
    );
    if (shape != null) return Err(shape);

    final updated = goal.copyWith(name: trimmedName, updatedAt: _now());

    try {
      await db.execute(
        SavingsSql.updateGoal,
        SavingsSql.updateGoalParams(updated.toColumns()),
      );
      return Ok(updated);
    } on Exception catch (e, st) {
      _log.severe('Falha ao salvar meta', e, st);
      return Err(DatabaseFailure('Não foi possível salvar a meta.', cause: e));
    }
  }

  @override
  Future<Result<void, Failure>> deleteGoal(String goalId) async {
    try {
      // As duas exclusões numa transação só: um crash no meio deixaria
      // contribuição órfã contando no total da tela.
      await db.writeTransaction((tx) async {
        await tx.execute(SavingsSql.deleteContributionsOfGoal, [goalId]);
        await tx.execute(SavingsSql.deleteGoal, [goalId]);
      });
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover meta', e, st);
      return Err(DatabaseFailure('Não foi possível remover a meta.', cause: e));
    }
  }

  @override
  Future<Result<SavingsContribution, Failure>> addContribution({
    required SavingsGoal goal,
    required Money amount,
    DateTime? contributedAt,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(
        AuthFailure('Nenhuma sessão ativa para registrar contribuição.'),
      );
    }

    if (!amount.isPositive) {
      return const Err(
        ValidationFailure('O valor guardado deve ser maior que zero.'),
      );
    }
    if (amount.currency != goal.currency) {
      return const Err(
        ValidationFailure('O valor precisa estar na moeda da meta.'),
      );
    }

    final timestamp = _now();
    final contribution = SavingsContribution(
      id: _genId(),
      goalId: goal.id,
      // O SQLite local não tem o trigger que o Postgres tem, então o espaço vem
      // da meta aqui: sem isso a linha nasceria fora do bucket e sumiria da UI.
      spaceId: goal.spaceId,
      createdBy: userId,
      amount: amount,
      source: ContributionSource.manual,
      // Manual já nasce confirmado — quem digitou o valor confirmou junto.
      isConfirmed: true,
      contributedAt: contributedAt ?? timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    try {
      await db.execute(
        SavingsSql.insertContribution,
        SavingsSql.insertContributionParams(contribution.toColumns()),
      );
      return Ok(contribution);
    } on Exception catch (e, st) {
      _log.severe('Falha ao registrar contribuição', e, st);
      return Err(
        DatabaseFailure('Não foi possível registrar o valor.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> confirmContribution(
    String contributionId,
  ) async {
    try {
      await db.execute(SavingsSql.confirmContribution, [
        _now().toIso8601String(),
        contributionId,
      ]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao confirmar contribuição', e, st);
      return Err(
        DatabaseFailure('Não foi possível confirmar a contribuição.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> deleteContribution(
    String contributionId,
  ) async {
    try {
      await db.execute(SavingsSql.deleteContribution, [contributionId]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover contribuição', e, st);
      return Err(
        DatabaseFailure('Não foi possível remover a contribuição.', cause: e),
      );
    }
  }

  /// Espelha o `savings_goals_shape_ck` da migration, em português.
  ///
  /// Existe para o usuário receber uma frase em vez de um erro de constraint: a
  /// escrita local falharia de qualquer forma, mas com uma mensagem do SQLite
  /// que não diz o que fazer. `targetDate` não entra: prazo é opcional, e prazo
  /// no passado é uma meta perdida — dado legítimo, não erro de preenchimento.
  static ValidationFailure? _validateShape({
    required SavingsGoalType type,
    required Money? targetAmount,
    required int? percentage,
  }) => switch (type) {
    SavingsGoalType.objective || SavingsGoalType.fixedAmount =>
      (targetAmount == null || !targetAmount.isPositive)
          ? const ValidationFailure('Informe um valor maior que zero.')
          : null,
    SavingsGoalType.percentageIncome =>
      (percentage == null || percentage < 1 || percentage > 100)
          ? const ValidationFailure('O percentual deve ficar entre 1 e 100.')
          : null,
  };
}
