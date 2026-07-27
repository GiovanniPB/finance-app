import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/account.dart';
import '../domain/accounts_repository.dart';

/// Statements de conta, em constantes para o teste de guarda rodá-las contra
/// uma view igual à que o PowerSync cria.
///
/// As tabelas locais do PowerSync são **views com triggers `INSTEAD OF`**, e o
/// SQLite recusa construções que uma tabela aceitaria (foi assim que o UPSERT
/// de orçamento passou meses quebrado com o teste verde: mock de conexão
/// compara o *texto* do SQL e não sabe distinguir SQL válido de SQL recusado).
abstract final class AccountSql {
  /// Só as contas do dono. Ver o comentário de `watchOwned` no contrato.
  static const watchOwned =
      'SELECT * FROM accounts WHERE owner_id = ? ORDER BY created_at DESC';

  /// As do dono mais as que outros membros vincularam a este household.
  static const watchForSpace =
      'SELECT * FROM accounts WHERE owner_id = ? OR linked_space_id = ? '
      'ORDER BY created_at DESC';

  static const insert =
      'INSERT INTO accounts (id, owner_id, linked_space_id, name, '
      'account_type, institution, currency, current_balance_minor, '
      'balance_as_of, is_savings_target, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  /// `owner_id` e `created_at` ficam de fora: são a identidade da linha, não
  /// dado editável.
  static const update =
      'UPDATE accounts SET linked_space_id = ?, name = ?, account_type = ?, '
      'institution = ?, currency = ?, current_balance_minor = ?, '
      'balance_as_of = ?, is_savings_target = ?, updated_at = ? WHERE id = ?';

  static const deleteById = 'DELETE FROM accounts WHERE id = ?';

  /// Ordem dos parâmetros do [insert], a partir de `toColumns()`.
  static List<Object?> insertParams(Map<String, Object?> cols) => [
    cols['id'],
    cols['owner_id'],
    cols['linked_space_id'],
    cols['name'],
    cols['account_type'],
    cols['institution'],
    cols['currency'],
    cols['current_balance_minor'],
    cols['balance_as_of'],
    cols['is_savings_target'],
    cols['created_at'],
    cols['updated_at'],
  ];

  /// Ordem dos parâmetros do [update], a partir de `toColumns()`.
  static List<Object?> updateParams(Map<String, Object?> cols) => [
    cols['linked_space_id'],
    cols['name'],
    cols['account_type'],
    cols['institution'],
    cols['currency'],
    cols['current_balance_minor'],
    cols['balance_as_of'],
    cols['is_savings_target'],
    cols['updated_at'],
    cols['id'],
  ];
}

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
        .watch(AccountSql.watchOwned, parameters: [userId])
        .map((results) => results.map(Account.fromRow).toList());
  }

  @override
  Stream<List<Account>> watchForSpace(String spaceId) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value(const []);

    return db
        .watch(AccountSql.watchForSpace, parameters: [userId, spaceId])
        .map((results) => results.map(Account.fromRow).toList());
  }

  @override
  Future<Result<Account, Failure>> create({
    required String name,
    AccountType type = AccountType.checking,
    Money currentBalance = const Money.zero(),
    bool isSavingsTarget = false,
    String? institution,
    String? linkedSpaceId,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(AuthFailure('Nenhuma sessão ativa para criar conta.'));
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return const Err(ValidationFailure('Informe um nome para a conta.'));
    }

    final timestamp = _now();
    final account = Account(
      id: _genId(),
      ownerId: userId,
      name: trimmedName,
      type: type,
      currentBalance: currentBalance,
      balanceAsOf: timestamp,
      isSavingsTarget: isSavingsTarget,
      createdAt: timestamp,
      updatedAt: timestamp,
      institution: _blankToNull(institution),
      linkedSpaceId: linkedSpaceId,
    );

    try {
      await db.execute(
        AccountSql.insert,
        AccountSql.insertParams(account.toColumns()),
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
  Future<Result<Account, Failure>> update(
    Account account, {
    bool balanceChanged = false,
  }) async {
    final trimmedName = account.name.trim();
    if (trimmedName.isEmpty) {
      return const Err(ValidationFailure('Informe um nome para a conta.'));
    }

    final timestamp = _now();
    final updated = account.copyWith(
      name: trimmedName,
      institution: _blankToNull(account.institution),
      // Só um saldo novo renova a data do saldo. Corrigir o nome não torna o
      // número mais recente, e afirmar que torna é pior que não dizer nada.
      balanceAsOf: balanceChanged ? timestamp : account.balanceAsOf,
      updatedAt: timestamp,
    );

    try {
      await db.execute(
        AccountSql.update,
        AccountSql.updateParams(updated.toColumns()),
      );
      return Ok(updated);
    } on Exception catch (e, st) {
      _log.severe('Falha ao salvar conta', e, st);
      return Err(
        DatabaseFailure('Não foi possível salvar a conta.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      await db.execute(AccountSql.deleteById, [id]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover conta', e, st);
      return Err(
        DatabaseFailure('Não foi possível remover a conta.', cause: e),
      );
    }
  }

  /// Campo de texto vazio vira nulo: "sem instituição" e "instituição em
  /// branco" são o mesmo estado, e o check da migration recusa string vazia.
  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
