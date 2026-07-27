import 'package:core/core.dart';

import 'transaction.dart';

/// Contrato da camada de dados de transações.
///
/// Toda leitura é **com escopo de espaço** (ADR 0004): o SQLite local contém
/// vários espaços ao mesmo tempo, então uma query sem `space_id` vazaria dado
/// de outro espaço para a tela.
abstract interface class TransactionsRepository {
  /// Stream reativo das transações de um espaço, mais recentes primeiro.
  ///
  /// [from] inclusivo e [to] exclusivo delimitam a janela por `occurred_at`.
  /// Sem eles, traz o espaço inteiro — use com parcimônia.
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  });

  /// Cria uma transação localmente (entra na fila de upload do PowerSync).
  ///
  /// [amount] pode vir com qualquer sinal: a direção é determinada por [type],
  /// e o valor é persistido em módulo.
  Future<Result<Transaction, Failure>> create({
    required String spaceId,
    required TransactionType type,
    required Money amount,
    required DateTime occurredAt,
    String? accountId,
    String? categoryId,
    String? description,
    bool isShared = false,
  });

  /// Atualiza os campos editáveis de uma transação existente.
  Future<Result<Transaction, Failure>> update(Transaction transaction);

  /// Remove uma transação pelo id.
  Future<Result<void, Failure>> delete(String id);
}
