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
  ///
  /// [currentBalance] é o saldo que o usuário informa hoje — um snapshot, não
  /// uma soma de lançamentos (ver [Account]). O sinal é descartado na
  /// gravação: quem carrega a direção é [type].
  Future<Result<Account, Failure>> create({
    required String name,
    AccountType type = AccountType.checking,
    Money currentBalance = const Money.zero(),
    bool isSavingsTarget = false,
    String? institution,
    String? linkedSpaceId,
  });

  /// Grava as alterações de uma conta existente.
  ///
  /// Só o dono edita, mesmo quando a conta está vinculada a um household — é a
  /// soberania do dono do ADR 0004, garantida pelo RLS no servidor.
  Future<Result<Account, Failure>> update(Account account);

  /// Remove uma conta pelo id.
  ///
  /// Os lançamentos que apontavam para ela **não** são apagados: a FK é
  /// `on delete set null`, então eles ficam sem conta em vez de sumir.
  Future<Result<void, Failure>> delete(String id);
}
