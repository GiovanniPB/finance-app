import 'package:core/core.dart';

import 'settlement.dart';

/// Contrato da camada de dados do acerto de contas (RN-2.2).
///
/// ─────────────────────────────────────────────────────────────────────────
/// POR QUE ISTO NÃO É MÉTODO EM `TransactionsRepository`
///
/// O saldo lê `transactions` e `expense_splits`, então tecnicamente caberia lá.
/// Mas seis fakes de teste implementam aquela interface, e cada método novo
/// custa seis arquivos de churn que não têm nada a ver com a fatia. Interface
/// própria mantém o custo onde ele pertence: um fake, no teste que o usa.
abstract interface class SettlementRepository {
  /// Stream reativo do "quem deve a quem" de um espaço.
  ///
  /// Emite [Settlement.nothingSplit] enquanto não houver despesa dividida — que
  /// é diferente de tudo quite, e a UI diz coisas diferentes nos dois casos.
  Stream<Settlement> watch(String spaceId);

  /// Registra que [fromUserId] pagou [amount] a [toUserId].
  ///
  /// Grava um lançamento `transfer` com `paid_by = fromUserId` e **uma** parte
  /// para [toUserId], na mesma transação local. Não há tabela de acertos: a
  /// fórmula `pagou − deve` absorve as duas linhas e zera o par (ver o contrato
  /// da fatia `acertar-contas`).
  ///
  /// Recusa o que não é acerto: valor não positivo, as duas pontas iguais, e
  /// espaço que não é `group`.
  Future<Result<void, Failure>> settle({
    required String spaceId,
    required String fromUserId,
    required String toUserId,
    required Money amount,
    String? description,
  });
}
