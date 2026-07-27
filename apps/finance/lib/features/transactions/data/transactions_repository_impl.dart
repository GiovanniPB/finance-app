import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/transaction.dart';
import '../domain/transactions_repository.dart';

/// Implementação sobre o PowerSync (SQL bruto). Leituras via `watch`
/// (reativas), escritas via `execute` (persistem local e entram na fila de
/// upload). Depende de [SqliteConnection] para permitir teste com mocks.
class TransactionsRepositoryImpl implements TransactionsRepository {
  TransactionsRepositoryImpl({
    required this.db,
    required this.supabase,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('TransactionsRepository');

  final SqliteConnection db;
  final SupabaseClient supabase;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  static const _columns =
      'id, space_id, account_id, created_by, type, amount_minor, currency, '
      'category_id, description, occurred_at, source, is_shared, '
      'ai_categorized, recurrence_id, created_at, updated_at';

  @override
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) {
    final where = StringBuffer('space_id = ?');
    final params = <Object?>[spaceId];
    if (from != null) {
      where.write(' AND occurred_at >= ?');
      params.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND occurred_at < ?');
      params.add(to.toUtc().toIso8601String());
    }

    return db
        .watch(
          'SELECT * FROM transactions WHERE $where '
          'ORDER BY occurred_at DESC, created_at DESC',
          parameters: params,
        )
        .map((results) => results.map(Transaction.fromRow).toList());
  }

  @override
  Future<Result<Transaction, Failure>> create({
    required String spaceId,
    required TransactionType type,
    required Money amount,
    required DateTime occurredAt,
    String? accountId,
    String? categoryId,
    String? description,
    bool isShared = false,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(
        AuthFailure('Nenhuma sessão ativa para registrar transação.'),
      );
    }
    if (amount.isZero) {
      return const Err(
        ValidationFailure('Informe um valor maior que zero.'),
      );
    }

    // O domínio guarda sinal; o tipo é a fonte de verdade da direção.
    final signed = type.isOutflow ? -amount.abs : amount.abs;
    final timestamp = _now();
    final transaction = Transaction(
      id: _genId(),
      spaceId: spaceId,
      createdBy: userId,
      type: type,
      amount: signed,
      occurredAt: occurredAt,
      source: TransactionSource.manual,
      isShared: isShared,
      aiCategorized: false,
      createdAt: timestamp,
      updatedAt: timestamp,
      accountId: accountId,
      categoryId: categoryId,
      description: description,
    );

    try {
      final cols = transaction.toColumns();
      await db.execute(
        'INSERT INTO transactions ($_columns) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          cols['id'],
          cols['space_id'],
          cols['account_id'],
          cols['created_by'],
          cols['type'],
          cols['amount_minor'],
          cols['currency'],
          cols['category_id'],
          cols['description'],
          cols['occurred_at'],
          cols['source'],
          cols['is_shared'],
          cols['ai_categorized'],
          cols['recurrence_id'],
          cols['created_at'],
          cols['updated_at'],
        ],
      );
      return Ok(transaction);
    } on Exception catch (e, st) {
      _log.severe('Falha ao criar transação', e, st);
      return Err(
        DatabaseFailure('Não foi possível registrar a transação.', cause: e),
      );
    }
  }

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async {
    final updated = transaction.copyWith(updatedAt: _now());
    try {
      final cols = updated.toColumns();
      await db.execute(
        'UPDATE transactions SET type = ?, amount_minor = ?, currency = ?, '
        'category_id = ?, description = ?, occurred_at = ?, account_id = ?, '
        'is_shared = ?, updated_at = ? WHERE id = ?',
        [
          cols['type'],
          cols['amount_minor'],
          cols['currency'],
          cols['category_id'],
          cols['description'],
          cols['occurred_at'],
          cols['account_id'],
          cols['is_shared'],
          cols['updated_at'],
          updated.id,
        ],
      );
      return Ok(updated);
    } on Exception catch (e, st) {
      _log.severe('Falha ao atualizar transação', e, st);
      return Err(
        DatabaseFailure('Não foi possível salvar a transação.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      await db.execute('DELETE FROM transactions WHERE id = ?', [id]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover transação', e, st);
      return Err(
        DatabaseFailure('Não foi possível remover a transação.', cause: e),
      );
    }
  }
}
