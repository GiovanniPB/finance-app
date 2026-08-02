import 'package:core/core.dart';

import 'expense_split.dart';
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

  // -----------------------------------------------------------------------
  // Divisão de despesa (RN-2.1)
  //
  // MARCAR E RATEAR SÃO UMA OPERAÇÃO, NÃO DUAS. `is_shared` e as N partes
  // sobem na mesma transação local: um lançamento marcado sem partes a UI leria
  // como "dividido entre ninguém", e partes sem a marca não apareceriam na
  // lista. É o mesmo argumento que obriga espaço e membership a nascerem
  // juntos.
  // -----------------------------------------------------------------------

  /// As partes de um lançamento, na ordem de entrada de cada membro.
  ///
  /// Lista vazia = lançamento não dividido. Não há estado intermediário: ver o
  /// bloco acima.
  Stream<List<ExpenseSplit>> watchSplits(String transactionId);

  /// Divide o lançamento igualmente entre os **membros ativos** do espaço.
  ///
  /// Idempotente por refazer: apaga as partes que existirem e insere as novas,
  /// então tocar duas vezes não dobra o rateio. Chamar de novo depois de o
  /// valor mudar é o que mantém a soma das partes igual ao total — e é
  /// exatamente o que `update` faz quando o lançamento já está dividido.
  ///
  /// Recusa o que não se rateia: tipo diferente de `expense`, espaço que não é
  /// `group`, e lançamento inexistente.
  Future<Result<List<ExpenseSplit>, Failure>> splitEqually(
    String transactionId,
  );

  /// Desfaz a divisão: apaga as partes e limpa `is_shared`, numa transação só.
  Future<Result<void, Failure>> removeSplit(String transactionId);
}
