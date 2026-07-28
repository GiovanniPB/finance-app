import 'package:freezed_annotation/freezed_annotation.dart';

part 'open_finance_connection.freezed.dart';

/// Saúde de uma conexão bancária, no **nosso** vocabulário.
///
/// A Pluggy tem mais de uma dúzia de `executionStatus`. Traduzir todos para
/// estados de tela faria a UI mudar quando o fornecedor renomeasse um enum.
/// Por isso `provider_execution_status` guarda o texto cru deles, para
/// diagnóstico, e este enum fica curto e estável (ver o item 2 do cabeçalho da
/// migration 20260728033219).
enum ConnectionStatus {
  /// Criada; a primeira sincronização ainda não terminou.
  pending,
  active,

  /// A credencial do banco mudou. Exige o usuário reconectar.
  loginError,

  /// MFA pendente: a Pluggy espera um código que só o usuário tem.
  waitingUserInput,

  /// A Pluggy não conseguiu atualizar. Costuma resolver sozinho.
  outdated,

  /// O consentimento do Open Finance venceu — o único que a UI transforma em
  /// pedido de re-consentimento (ADR 0005).
  consentExpired,

  /// Removida na Pluggy.
  deleted,

  /// Valor que este app não conhece.
  ///
  /// **Diferente de `AccountType.fromDb`, que lança.** Aqui um status
  /// desconhecido não pode derrubar a tela, por duas razões: o vocabulário é
  /// escrito pelo **servidor** (a ingestão e o webhook), e a tabela local do
  /// PowerSync é uma view — o `check` do Postgres não vale nela, o que está
  /// provado em `open_finance_persistence_test.dart`. Uma versão nova do
  /// servidor gravando um status novo faria toda a lista de bancos estourar num
  /// app antigo.
  unknown;

  static ConnectionStatus fromDb(String? value) => switch (value) {
    'pending' => ConnectionStatus.pending,
    'active' => ConnectionStatus.active,
    'login_error' => ConnectionStatus.loginError,
    'waiting_user_input' => ConnectionStatus.waitingUserInput,
    'outdated' => ConnectionStatus.outdated,
    'consent_expired' => ConnectionStatus.consentExpired,
    'deleted' => ConnectionStatus.deleted,
    _ => ConnectionStatus.unknown,
  };

  String get db => switch (this) {
    ConnectionStatus.pending => 'pending',
    ConnectionStatus.active => 'active',
    ConnectionStatus.loginError => 'login_error',
    ConnectionStatus.waitingUserInput => 'waiting_user_input',
    ConnectionStatus.outdated => 'outdated',
    ConnectionStatus.consentExpired => 'consent_expired',
    ConnectionStatus.deleted => 'deleted',
    // `unknown` nunca é escrito: ele só existe na leitura, para tolerar um
    // vocabulário mais novo que o nosso. Gravá-lo apagaria a informação real.
    ConnectionStatus.unknown => 'pending',
  };

  /// Se o usuário precisa fazer algo para a sincronização voltar.
  ///
  /// [outdated] fica de fora de propósito: a Pluggy costuma se recuperar na
  /// próxima janela de auto-sync, e pedir ação para algo que se resolve sozinho
  /// treina o usuário a ignorar o aviso.
  bool get needsUserAction => switch (this) {
    ConnectionStatus.loginError ||
    ConnectionStatus.waitingUserInput ||
    ConnectionStatus.consentExpired => true,
    ConnectionStatus.pending ||
    ConnectionStatus.active ||
    ConnectionStatus.outdated ||
    ConnectionStatus.deleted ||
    ConnectionStatus.unknown => false,
  };

  /// Frase curta para a linha da lista.
  ///
  /// `unknown` não diz "desconhecido" ao usuário — isso é vocabulário de
  /// programador. Diz que está sincronizando, que é o que ele precisa saber.
  String get label => switch (this) {
    ConnectionStatus.pending => 'Sincronizando pela primeira vez',
    ConnectionStatus.active => 'Conectado',
    ConnectionStatus.loginError => 'A senha do banco mudou',
    ConnectionStatus.waitingUserInput => 'Falta confirmar um código',
    ConnectionStatus.outdated => 'Tentando atualizar',
    ConnectionStatus.consentExpired => 'Autorização vencida',
    ConnectionStatus.deleted => 'Removido no banco',
    ConnectionStatus.unknown => 'Sincronizando',
  };
}

/// Uma instituição conectada por Open Finance — um `item` da Pluggy.
///
/// Pertence ao **dono**, não a um espaço: o consentimento do Open Finance é
/// pessoal e intransferível, e quem revoga é o titular. Um household vê as
/// **contas** vinculadas, nunca a credencial que as alimenta (ver o item 1 do
/// cabeçalho da migration 20260728033219).
@freezed
abstract class OpenFinanceConnection with _$OpenFinanceConnection {
  const factory OpenFinanceConnection({
    required String id,
    required String ownerId,

    /// O `itemId` da Pluggy. Único no banco: um item pertence a um usuário só.
    required String itemId,
    required ConnectionStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    int? connectorId,

    /// Nome da instituição, capturado do widget. Guardado em vez de re-buscado
    /// porque a lista precisa renderizar offline.
    String? connectorName,
    String? connectorImageUrl,

    /// Texto cru da Pluggy, para diagnóstico. Nunca vai para a tela.
    String? providerExecutionStatus,
    String? providerStatusDetail,
    DateTime? consentExpiresAt,
    DateTime? lastSyncedAt,
    DateTime? nextAutoSyncAt,
  }) = _OpenFinanceConnection;

  const OpenFinanceConnection._();

  factory OpenFinanceConnection.fromRow(Map<String, Object?> row) =>
      OpenFinanceConnection(
        id: row['id']! as String,
        ownerId: row['owner_id']! as String,
        itemId: row['item_id']! as String,
        status: ConnectionStatus.fromDb(row['status'] as String?),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        connectorId: row['connector_id'] as int?,
        connectorName: row['connector_name'] as String?,
        connectorImageUrl: row['connector_image_url'] as String?,
        providerExecutionStatus: row['provider_execution_status'] as String?,
        providerStatusDetail: row['provider_status_detail'] as String?,
        consentExpiresAt: _parseOptional(row['consent_expires_at']),
        lastSyncedAt: _parseOptional(row['last_synced_at']),
        nextAutoSyncAt: _parseOptional(row['next_auto_sync_at']),
      );

  static DateTime? _parseOptional(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;

  /// Nome a exibir. Conexão sem `connector_name` (linha gravada antes de o
  /// widget informar a instituição) não pode aparecer em branco na lista.
  String get displayName => connectorName?.trim().isNotEmpty ?? false
      ? connectorName!.trim()
      : 'Banco conectado';
}
