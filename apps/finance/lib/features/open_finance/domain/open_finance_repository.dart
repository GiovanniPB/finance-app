import 'package:core/core.dart';

import 'open_finance_connection.dart';

/// Contrato de acesso às conexões de Open Finance.
///
/// Duas naturezas de operação convivem aqui, e vale saber qual é qual:
///
///  * **Local e offline-first** ([watchAll], [save], [delete]) — SQL sobre o
///    SQLite do PowerSync, que sincroniza sozinho.
///  * **Rede, agora** ([requestConnectToken]) — chama a Edge Function
///    `pluggy-connect-token`. Não tem versão offline: sem internet não há como
///    conectar um banco, e fingir o contrário deixaria o usuário num widget que
///    não carrega.
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

  /// Remove a conexão **do nosso banco**.
  ///
  /// Não revoga nada na Pluggy: isso exige a API Key e é trabalho de servidor
  /// (`DELETE /items/{id}`), que entra com o worker. Até lá, remover aqui para
  /// de mostrar a conexão e **não** apaga as contas nem os lançamentos que ela
  /// trouxe — a FK é `on delete set null`, porque o dinheiro passou de verdade
  /// e quem terminou foi o vínculo.
  Future<Result<void, Failure>> delete(String id);
}
