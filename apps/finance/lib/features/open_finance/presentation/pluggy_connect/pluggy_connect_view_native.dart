import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'pluggy_connect_event.dart';
import 'pluggy_connect_guards.dart';
import 'pluggy_connect_url.dart';

/// O widget Pluggy Connect dentro de um WebView.
///
/// ─────────────────────────────────────────────────────────────────────────
/// POR QUE ISTO É CÓDIGO NOSSO E NÃO O PACOTE OFICIAL
///
/// Existe um `flutter_pluggy_connect` publicado pela própria Pluggy (publisher
/// `pluggy.ai`). Ele foi lido inteiro — 436 linhas — e internalizado em vez de
/// adotado, por três lacunas concretas, todas verificadas na 3.0.1:
///
///  1. **Nenhum `onNavigationRequest`**, em nenhum lugar do pacote. O WebView
///     seguia qualquer navegação. Aqui, [decideNavigation] só libera hosts da
///     Pluggy — e uma navegação recusada vai para o log em vez de virar tela
///     branca sem explicação.
///  2. **`launchUrl` com a URL vinda do JS, sem validar nada.** Qualquer coisa
///     que a página postasse no canal era entregue ao sistema operacional. Aqui
///     [canOpenExternally] exige HTTPS com host, o que barra `javascript:`,
///     `file:`, `data:` e `intent:`. Allowlist de host é impossível neste ponto
///     (o destino é o banco que o usuário escolheu, entre centenas).
///  3. **Mensagem de tipo desconhecido caía em `dynamic` sem tratamento.** Aqui
///     [parseMessageType] a transforma em `unknown`, que é ignorada.
///
/// Além disso o pacote está parado desde novembro de 2024, tem 3 likes, não
/// suporta web, e puxa `app_links` para um contorno que ele mesmo marca com
/// "TODO: find a better way to solve this". "Seguir o upstream" já não estava
/// acontecendo de fato.
///
/// **O que herdamos deles e é dívida real:** o protocolo de mensagens
/// (`OAUTH_OPEN`, `LINK_OPEN`, `LOCATION` e os nomes de evento na query) é
/// contrato **interno** e não documentado da Pluggy. Só se conhece por leitura
/// do fonte. Ver `pluggy_connect_event.dart`.
/// ─────────────────────────────────────────────────────────────────────────
class PluggyConnectView extends StatefulWidget {
  const PluggyConnectView({
    required this.connectToken,
    this.updateItemId,
    this.includeSandbox = false,
    this.onEvent,
    super.key,
  });

  /// Token efêmero emitido pela Edge Function `pluggy-connect-token`.
  final String connectToken;

  /// Quando presente, o widget entra em modo de **atualização** do item — o
  /// caminho de re-consentimento.
  final String? updateItemId;

  /// Expõe os conectores de sandbox (Pluggy Bank). É o que permite exercitar o
  /// fluxo sem banco real.
  final bool includeSandbox;

  /// Chamado a cada evento novo do fluxo. Quem decide o que fazer com
  /// [PluggyConnectSucceeded] é a camada de cima — este widget não escreve no
  /// banco.
  final ValueChanged<PluggyConnectEvent>? onEvent;

  @override
  State<PluggyConnectView> createState() => _PluggyConnectViewState();
}

class _PluggyConnectViewState extends State<PluggyConnectView> {
  static const _javaScriptChannel = 'pluggyConnectHandler';

  final _log = AppLogger('PluggyConnect');
  late final WebViewController _controller;

  /// Último `timestamp` visto. A página reposta a mesma localização várias
  /// vezes; sem isto, uma conexão seria gravada em duplicidade.
  String? _lastTimestamp;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    // Cada `set*` do controller devolve `Future`; configurar num método async
    // (em vez de cascata no construtor) é o que permite aguardá-los em ordem.
    unawaited(_configureController());
  }

  Future<void> _configureController() async {
    // O widget do Connect é uma aplicação JS: sem isto ele não roda. É o
    // motivo pelo qual as guardas de navegação acima não são opcionais.
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _onNavigationRequest,
        onWebResourceError: (error) => _log.warning(
          'Erro de recurso no WebView do Connect: ${error.description}',
        ),
      ),
    );
    await _controller.addJavaScriptChannel(
      _javaScriptChannel,
      onMessageReceived: (message) => _onJavaScriptMessage(message.message),
    );
    // Só carrega **depois** de delegate e canal instalados: carregar antes
    // abriria uma janela em que a página navega sem passar pela allowlist.
    await _controller.loadRequest(
      Uri.parse(
        buildPluggyConnectUrl(
          connectToken: widget.connectToken,
          updateItemId: widget.updateItemId,
          includeSandbox: widget.includeSandbox,
        ),
      ),
    );
  }

  /// `NavigationDecision` aqui é o tipo do `webview_flutter`; o nosso veredito
  /// se chama [NavigationVerdict] justamente para os dois não colidirem.
  FutureOr<NavigationDecision> _onNavigationRequest(
    NavigationRequest request,
  ) {
    if (decideNavigation(request.url) == NavigationVerdict.allow) {
      return NavigationDecision.navigate;
    }
    // Recusar em silêncio produziria uma tela que não carrega e nenhuma pista
    // do motivo. O host entra no log justamente para o caso de a Pluggy passar
    // a usar um domínio que a allowlist não conhece.
    _log.warning(
      'Navegação recusada no WebView do Connect: '
      '${Uri.tryParse(request.url)?.host ?? "url inválida"}',
    );
    return NavigationDecision.prevent;
  }

  void _onJavaScriptMessage(String raw) {
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      payload = decoded;
    } on FormatException {
      // Canal JS é entrada não confiável.
      return;
    }

    final content = payload['message'];
    final messageContent = content is String ? content : '';

    switch (parseMessageType(payload['type'] as String?)) {
      case PluggyMessageType.oauthOpen:
      case PluggyMessageType.linkOpen:
        unawaited(_openExternally(messageContent));
      case PluggyMessageType.location:
        _handleLocation(messageContent);
      case PluggyMessageType.unknown:
        // Ignorada de propósito: tipo que não conhecemos não pode ser tratado
        // como um dos outros.
        break;
    }
  }

  Future<void> _openExternally(String url) async {
    if (!canOpenExternally(url)) {
      _log.warning(
        'Link externo recusado pelo Connect '
        '(esquema ${Uri.tryParse(url)?.scheme ?? "inválido"})',
      );
      return;
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on PlatformException catch (e, st) {
      _log.warning('Não foi possível abrir o link do banco', e, st);
    }
  }

  void _handleLocation(String rawQuery) {
    final read = readPluggyLocation(rawQuery, lastTimestamp: _lastTimestamp);
    _lastTimestamp = read.timestamp;

    final event = read.event;
    if (event == null) return;
    widget.onEvent?.call(event);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
