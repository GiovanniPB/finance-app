import 'package:core/core.dart';

import 'open_finance_connection.dart';

/// Contrato de acesso às conexões de Open Finance.
///
/// Duas naturezas de operação convivem aqui, e vale saber qual é qual:
///
///  * **Local e offline-first** ([watchAll], [save], [delete]) — SQL sobre o
///    SQLite do PowerSync, que sincroniza sozinho.
///  * **Rede, agora** ([requestConnectToken], [revokeAccess]) — chamam Edge
///    Functions. Não têm versão offline: sem internet não há como conectar um
///    banco nem cancelar um acesso, e fingir o contrário deixaria o usuário num
///    widget que não carrega ou com um consentimento que ele acha revogado.
abstract interface class OpenFinanceRepository {
  /// Conexões do usuário, reativas. Vazio sem sessão.
  Stream<List<OpenFinanceConnection>> watchAll();

  /// Pede um Connect Token à nossa Edge Function.
  ///
  /// Com [updateItemId], o token serve para **atualizar** um item existente — o
  /// caminho de re-consentimento quando a autorização vence ou a senha do banco
  /// muda. Sem ele, a Pluggy bloqueia a atualização via widget por segurança.
  Future<Result<String, Failure>> requestConnectToken({String? updateItemId});

  /// Grava a conexão que o widget acabou de criar.
  ///
  /// O status nasce `pending`: o widget devolve o `itemId` assim que o login
  /// passa, mas a primeira sincronização ainda está em curso do lado da Pluggy.
  /// Dizer "Conectado" nesse instante prometeria dado que ainda não chegou.
  Future<Result<OpenFinanceConnection, Failure>> save({
    required String itemId,
    int? connectorId,
    String? connectorName,
  });

  /// Cancela o acesso ao banco no provedor (`DELETE /items/{id}`, pela Edge
  /// Function `pluggy-disconnect` — a chamada exige a API Key, que não sai do
  /// servidor).
  ///
  /// **Chame antes de [delete], e só apague a linha se isto deu certo.** Na
  /// ordem inversa, a linha desapareceria do app enquanto o consentimento
  /// continuasse valendo no banco, sem nada que apontasse para ele: a tela
  /// teria dito que o acesso foi cancelado e não haveria mais como cancelá-lo.
  ///
  /// Falhar aqui é o caso normal quando não há internet. Revogação é
  /// inerentemente online, e o erro diz isso.
  Future<Result<void, Failure>> revokeAccess(String connectionId);

  /// Remove a conexão **do nosso banco**.
  ///
  /// **Não** apaga as contas nem os lançamentos que ela trouxe — a FK é
  /// `on delete set null`, porque o dinheiro passou de verdade e quem terminou
  /// foi o vínculo. As contas viram contas comuns, com o histórico intacto.
  ///
  /// Quem cancela o acesso do lado do banco é [revokeAccess]. Se esta linha
  /// sobreviver a uma revogação bem-sucedida, o estado **se autocura**: a
  /// próxima passada do worker leva 404 no item e marca a conexão como
  /// removida.
  Future<Result<void, Failure>> delete(String id);
}
