import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/account.dart';
import '../domain/accounts_repository.dart';

/// Implementação sobre o PowerSync (SQL bruto). Leituras via `watch`
/// (reativas), escritas via `execute` (persistem local e entram na fila de
/// upload). Depende de [SqliteConnection] (interface implementada pelo
/// PowerSyncDatabase) para permitir teste com mocks.
class AccountsRepositoryImpl implements AccountsRepository {
  AccountsRepositoryImpl({
    required this.db,
    required this.supabase,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('AccountsRepository');

  final SqliteConnection db;
  final SupabaseClient supabase;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  @override
  Stream<List<Account>> watchOwned() {
    final userId = supabase.auth.currentUser?.id;
    // Sem sessão não há conta a exibir; evita vazar o banco local inteiro.
    if (userId == null) return Stream.value(const []);

    return db
        .watch(
          'SELECT * FROM accounts WHERE owner_id = ? ORDER BY created_at DESC',
          parameters: [userId],
        )
        .map((results) => results.map(Account.fromRow).toList());
  }

  @override
  Stream<List<Account>> watchForSpace(String spaceId) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value(const []);

    return db
        .watch(
          'SELECT * FROM accounts WHERE owner_id = ? OR linked_space_id = ? '
          'ORDER BY created_at DESC',
          parameters: [userId, spaceId],
        )
        .map((results) => results.map(Account.fromRow).toList());
  }

  @override
  Future<Result<Account, Failure>> create({
    required String name,
    String currency = 'BRL',
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(AuthFailure('Nenhuma sessão ativa para criar conta.'));
    }

    final account = Account(
      id: _genId(),
      ownerId: userId,
      name: name,
      currency: currency,
      createdAt: _now(),
      updatedAt: _now(),
    );

    try {
      final cols = account.toColumns();
      await db.execute(
        'INSERT INTO accounts (id, owner_id, name, currency, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          cols['id'],
          cols['owner_id'],
          cols['name'],
          cols['currency'],
          cols['created_at'],
          cols['updated_at'],
        ],
      );
      return Ok(account);
    } on Exception catch (e, st) {
      _log.severe('Falha ao criar conta', e, st);
      return Err(
        DatabaseFailure('Não foi possível criar a conta.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      await db.execute('DELETE FROM accounts WHERE id = ?', [id]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover conta', e, st);
      return Err(
        DatabaseFailure('Não foi possível remover a conta.', cause: e),
      );
    }
  }
}
