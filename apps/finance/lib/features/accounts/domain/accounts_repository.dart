import 'package:core/core.dart';

import 'account.dart';

/// Contrato da camada de dados de contas. O domínio depende desta interface,
/// nunca do PowerSync diretamente (ver decisão de persistência).
abstract interface class AccountsRepository {
  /// Stream reativo das contas do usuário (emite a cada mudança local/sync).
  Stream<List<Account>> watchAll();

  /// Cria uma conta localmente (entra na fila de upload do PowerSync).
  Future<Result<Account, Failure>> create({
    required String name,
    String currency = 'BRL',
  });

  /// Remove uma conta pelo id.
  Future<Result<void, Failure>> delete(String id);
}
