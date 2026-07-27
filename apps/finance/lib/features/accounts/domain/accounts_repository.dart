import 'package:core/core.dart';

import 'account.dart';

/// Contrato da camada de dados de contas. O domínio depende desta interface,
/// nunca do PowerSync diretamente (ver decisão de persistência).
abstract interface class AccountsRepository {
  /// Stream reativo das contas **do dono da sessão**.
  ///
  /// Filtra por `owner_id` de propósito: o SQLite local recebe também as contas
  /// que outros membros vincularam a um household compartilhado (ver sync
  /// rules), então um `SELECT *` sem filtro misturaria contas alheias na lista
  /// do usuário — ver ADR 0004.
  Stream<List<Account>> watchOwned();

  /// Stream reativo das contas visíveis num espaço: as do dono mais as que
  /// outros membros vincularam àquele household (`linked_space_id`).
  Stream<List<Account>> watchForSpace(String spaceId);

  /// Cria uma conta localmente (entra na fila de upload do PowerSync).
  Future<Result<Account, Failure>> create({
    required String name,
    String currency = 'BRL',
  });

  /// Remove uma conta pelo id.
  Future<Result<void, Failure>> delete(String id);
}
