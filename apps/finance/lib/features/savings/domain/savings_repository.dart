import 'package:core/core.dart';

import 'savings_contribution.dart';
import 'savings_goal.dart';

/// Contrato de persistência de metas de poupança e suas contribuições.
///
/// Metas e contribuições vivem no mesmo repositório porque não há caso de uso
/// para uma sem a outra: toda tela que mostra meta mostra progresso, e
/// progresso é agregação de contribuição (RN-3.3). Separá-los obrigaria toda
/// leitura a coordenar dois streams para responder a uma pergunta só.
abstract interface class SavingsRepository {
  /// Metas do espaço, mais recentes primeiro.
  Stream<List<SavingsGoal>> watchGoals(String spaceId);

  /// **Todas** as contribuições do espaço, de todas as metas.
  ///
  /// Um stream só, e não um por meta: a tela de Poupança precisa do progresso
  /// de cada meta ao mesmo tempo, e N streams para N metas multiplicariam os
  /// rebuilds sem reduzir o dado lido — o volume é o mesmo. O detalhe filtra em
  /// memória, como a lista de transações já faz com o mês.
  Stream<List<SavingsContribution>> watchContributions(String spaceId);

  Future<Result<SavingsGoal, Failure>> createGoal({
    required String spaceId,
    required SavingsGoalType type,
    required String name,
    Money? targetAmount,
    DateTime? targetDate,
    int? percentage,
    String? linkedAccountId,
  });

  Future<Result<SavingsGoal, Failure>> updateGoal(SavingsGoal goal);

  /// Remove a meta **e as contribuições dela**.
  ///
  /// O `on delete cascade` do Postgres cuida do servidor, mas as tabelas locais
  /// do PowerSync são views e não cascateiam: sem apagar as duas coisas aqui,
  /// as contribuições ficariam órfãs no SQLite local até o sync devolver a
  /// exclusão — e entrariam no total da tela nesse meio-tempo.
  Future<Result<void, Failure>> deleteGoal(String goalId);

  /// Registra "guardei R\$ X" (RN-3.2, caminho manual). Já nasce confirmado.
  ///
  /// Grava **duas linhas**: um lançamento `savings` (o dinheiro saiu do saldo
  /// gastável) e a contribuição que o referencia. São as duas faces de um
  /// evento só — enquanto só a contribuição existia, guardar dinheiro movia a
  /// meta e não aparecia em mais nenhum lugar do app: nem no total de saídas do
  /// mês, nem no saldo, nem na lista de lançamentos.
  ///
  /// [accountId] é a conta de onde o dinheiro **saiu**, e não a conta da meta
  /// (`linkedAccountId`, que é onde ele chegou). Nulo é aceito: o lançamento
  /// fica sem conta, como qualquer outro sem conta informada.
  Future<Result<SavingsContribution, Failure>> addContribution({
    required SavingsGoal goal,
    required Money amount,
    String? accountId,
    DateTime? contributedAt,
  });

  /// Confirma uma contribuição detectada pelo Open Finance (RN-3.2, caminho 2).
  ///
  /// É a confirmação que faz o valor entrar no progresso; até ela, a linha
  /// existe e não conta.
  Future<Result<void, Failure>> confirmContribution(String contributionId);

  /// Remove a contribuição **e o lançamento que a produziu**.
  ///
  /// Recebe a entidade, e não o id, justamente por causa do lançamento: o
  /// vínculo vive em `transactionId`, e pedir a entidade deixa explícito no
  /// tipo que a exclusão precisa saber dele. Contribuição sem lançamento
  /// (linha anterior à migration 20260728000822, ou detecção do Open Finance
  /// ainda sem lançamento nosso) sai sozinha.
  Future<Result<void, Failure>> deleteContribution(
    SavingsContribution contribution,
  );
}
