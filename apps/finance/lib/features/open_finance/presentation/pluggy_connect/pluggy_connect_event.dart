/// O que a página do Connect informa ao app, e como se lê isso.
///
/// A página posta mensagens `LOCATION` no canal JS, com uma query string que
/// carrega o estado do fluxo. **Contrato interno da Pluggy, não documentado
/// publicamente** — conhecido por leitura do fonte do pacote oficial deles
/// (`flutter_pluggy_connect` 3.0.1). Se o fluxo parar de funcionar sem nada
/// nosso ter mudado, é o primeiro lugar a suspeitar.
///
/// O evento corrente é o **último** item de `events` (lista separada por
/// vírgula, acumulada pela página), e `timestamp` é o que distingue mensagem
/// nova de repetição.
library;

/// Estado do fluxo do Connect, traduzido do contrato deles para o nosso.
sealed class PluggyConnectEvent {
  const PluggyConnectEvent();
}

/// O usuário concluiu a conexão. É o único evento que produz uma conexão nova:
/// o `itemId` daqui é o que o app grava em `open_finance_connections`.
final class PluggyConnectSucceeded extends PluggyConnectEvent {
  const PluggyConnectSucceeded({
    required this.itemId,
    this.itemStatus,
    this.executionStatus,
    this.connectorId,
    this.connectorName,
  });

  final String itemId;
  final String? itemStatus;
  final String? executionStatus;
  final int? connectorId;
  final String? connectorName;
}

/// O fluxo falhou. [message] vem da página e **é texto do fornecedor**: serve
/// para log, não para a tela (mesma regra do `authErrorMessage`).
final class PluggyConnectFailed extends PluggyConnectEvent {
  const PluggyConnectFailed({this.message, this.itemId});

  final String? message;
  final String? itemId;
}

/// O usuário fechou o widget sem concluir. Não é erro: desistir é uma escolha,
/// e tratar como falha mostraria mensagem de problema para quem só mudou de
/// ideia.
final class PluggyConnectClosed extends PluggyConnectEvent {
  const PluggyConnectClosed();
}

/// Passo intermediário (instituição escolhida, login enviado, MFA enviado…).
/// Útil para telemetria e para a tela saber que algo está acontecendo; nenhum
/// deles conclui a conexão.
final class PluggyConnectProgress extends PluggyConnectEvent {
  const PluggyConnectProgress({
    required this.eventType,
    this.itemId,
    this.connectorId,
    this.connectorName,
  });

  final String eventType;
  final String? itemId;
  final int? connectorId;
  final String? connectorName;
}

/// Resultado da leitura de uma mensagem `LOCATION`.
class PluggyLocationRead {
  const PluggyLocationRead({required this.event, required this.timestamp});

  /// Nulo quando a mensagem não trouxe evento novo — inclusive quando o
  /// `timestamp` repete o da anterior, que a página faz com frequência.
  final PluggyConnectEvent? event;

  /// Para o chamador guardar e comparar na mensagem seguinte.
  final String? timestamp;
}

/// Lê a query string de uma mensagem `LOCATION`.
///
/// [lastTimestamp] é o da leitura anterior; mensagem com o mesmo `timestamp` é
/// repetição e devolve evento nulo.
PluggyLocationRead readPluggyLocation(
  String rawQuery, {
  String? lastTimestamp,
}) {
  // A página manda a URL inteira ou só a query, com ou sem `?`. Normalizar aqui
  // evita um parser que funciona num caso e cala no outro.
  final queryStart = rawQuery.indexOf('?');
  final query = queryStart >= 0 ? rawQuery.substring(queryStart + 1) : rawQuery;

  // Query malformada vinda do canal JS não pode derrubar a tela, e ela chega
  // por **duas** famílias de exceção: `Uri.splitQueryString` lança
  // `FormatException` em alguns casos e `ArgumentError` em percent-encoding
  // inválido (`%%%`, `%zz`). A primeira versão tratava só a primeira e deixava
  // a outra subir — descoberto por teste, não por leitura.
  final Map<String, String> parameters;
  try {
    parameters = Uri.splitQueryString(query);
  } on FormatException {
    return PluggyLocationRead(event: null, timestamp: lastTimestamp);
    // `avoid_catching_errors` existe porque capturar `Error` costuma esconder
    // bug de programação. Aqui o `Error` não descreve bug nosso: descreve
    // entrada malformada de um canal JS, que é dado não confiável.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return PluggyLocationRead(event: null, timestamp: lastTimestamp);
  }

  final timestamp = parameters['timestamp'];
  final events = parameters['events'];
  final eventType = events?.split(',').last.trim();

  if (eventType == null || eventType.isEmpty) {
    return PluggyLocationRead(event: null, timestamp: lastTimestamp);
  }
  if (timestamp != null && timestamp == lastTimestamp) {
    return PluggyLocationRead(event: null, timestamp: lastTimestamp);
  }

  final itemId = parameters['item_id'];
  final connectorId = int.tryParse(parameters['connector_id'] ?? '');
  final connectorName = parameters['connector_name'];

  final event = switch (eventType) {
    // `SUCCESS` sem `item_id` não é sucesso utilizável: sem o item não há o que
    // gravar. Vira falha para não criar conexão órfã.
    'SUCCESS' when itemId != null && itemId.isNotEmpty =>
      PluggyConnectSucceeded(
        itemId: itemId,
        itemStatus: parameters['item_status'],
        executionStatus: parameters['execution_status'],
        connectorId: connectorId,
        connectorName: connectorName,
      ),
    'SUCCESS' => const PluggyConnectFailed(
      message: 'SUCCESS sem item_id',
    ),
    'ERROR' => PluggyConnectFailed(
      message: parameters['error'],
      itemId: itemId,
    ),
    'CLOSE' => const PluggyConnectClosed(),
    _ => PluggyConnectProgress(
      eventType: eventType,
      itemId: itemId,
      connectorId: connectorId,
      connectorName: connectorName,
    ),
  };

  return PluggyLocationRead(
    event: event,
    timestamp: timestamp ?? lastTimestamp,
  );
}
