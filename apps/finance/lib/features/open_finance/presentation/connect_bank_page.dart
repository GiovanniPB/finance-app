import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../domain/open_finance_connection.dart';
import 'pluggy_connect/pluggy_connect_event.dart';
import 'pluggy_connect/pluggy_connect_view.dart';

/// Tela cheia do fluxo de conectar banco.
///
/// **Por que tela cheia e não folha.** Todo o resto do app usa
/// `showModalBottomSheet`, mas aqui quem desenha a interface é a Pluggy: são
/// várias etapas (escolher instituição, login, MFA), com teclado, e uma folha a
/// meia altura obrigaria a rolar dentro de um WebView que já rola. É a exceção
/// que a natureza do conteúdo justifica.
///
/// **Ordem das coisas:** pedir o token à nossa Edge Function → montar o widget
/// → no `SUCCESS`, gravar a conexão → fechar. O token é pedido **aqui** e não
/// no widget porque é a única parte do fluxo que é nossa: o widget recebe um
/// token pronto e não sabe de onde veio.
class ConnectBankPage extends ConsumerStatefulWidget {
  const ConnectBankPage({this.updateItemId, super.key});

  /// Quando presente, o fluxo é de **re-consentimento** de uma conexão que já
  /// existe: autorização vencida ou senha do banco trocada.
  final String? updateItemId;

  /// Abre o fluxo. Devolve a conexão gravada, ou nulo se o usuário desistiu ou
  /// algo falhou.
  static Future<OpenFinanceConnection?> show(
    BuildContext context, {
    String? updateItemId,
  }) => Navigator.of(context).push<OpenFinanceConnection>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ConnectBankPage(updateItemId: updateItemId),
    ),
  );

  @override
  ConsumerState<ConnectBankPage> createState() => _ConnectBankPageState();
}

class _ConnectBankPageState extends ConsumerState<ConnectBankPage> {
  final _log = AppLogger('ConnectBankPage');

  String? _connectToken;
  String? _errorMessage;

  /// Trava contra gravar duas vezes. O widget pode emitir `SUCCESS` mais de uma
  /// vez; o repository também deduplica por `item_id`, mas evitar a segunda
  /// chamada aqui poupa uma ida ao banco e um `pop` duplicado — e `pop` duplo
  /// fecharia a tela de trás.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_requestToken());
  }

  Future<void> _requestToken() async {
    setState(() => _errorMessage = null);

    final result = await ref
        .read(openFinanceRepositoryProvider)
        .requestConnectToken(updateItemId: widget.updateItemId);

    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() => _connectToken = value);
      case Err(:final failure):
        // A frase já vem em português: a Edge Function escreve `{"error"}` para
        // a tela, e o repository traduz o que ela não previu.
        setState(() => _errorMessage = failure.message);
    }
  }

  Future<void> _onConnectEvent(PluggyConnectEvent event) async {
    switch (event) {
      case PluggyConnectSucceeded(
        :final itemId,
        :final connectorId,
        :final connectorName,
      ):
        await _save(
          itemId: itemId,
          connectorId: connectorId,
          connectorName: connectorName,
        );
      case PluggyConnectFailed(:final message):
        // `message` é texto do fornecedor, em inglês: vai para o log, não
        // para a tela. Mesma regra do `authErrorMessage`.
        _log.warning('Fluxo do Connect falhou: ${message ?? "sem detalhe"}');
        if (!mounted) return;
        setState(
          () => _errorMessage =
              'Não foi possível concluir a conexão com o banco. '
              'Tente de novo.',
        );
      case PluggyConnectClosed():
        // Desistir é uma escolha, não erro: fecha sem mensagem nenhuma.
        if (mounted) Navigator.of(context).pop();
      case PluggyConnectProgress():
        // Etapa intermediária: nada a fazer. O widget já mostra o próprio
        // progresso, e duplicá-lo numa barra nossa competiria com ele.
        break;
    }
  }

  Future<void> _save({
    required String itemId,
    int? connectorId,
    String? connectorName,
  }) async {
    if (_saving) return;
    _saving = true;

    final result = await ref
        .read(openFinanceRepositoryProvider)
        .save(
          itemId: itemId,
          connectorId: connectorId,
          connectorName: connectorName,
        );

    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        _saving = false;
        setState(() => _errorMessage = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.updateItemId == null ? 'Conectar banco' : 'Reconectar banco',
      ),
    ),
    body: _body(),
  );

  Widget _body() {
    final error = _errorMessage;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: AppEmptyState(
            key: const Key('connect_error'),
            icon: Icons.link_off,
            title: 'A conexão não foi concluída',
            message: error,
            actionLabel: 'Tentar de novo',
            onAction: _requestToken,
          ),
        ),
      );
    }

    final token = _connectToken;
    if (token == null) {
      // Pedir o token é ida à rede. Um spinner sem texto aqui leria como tela
      // travada, porque a espera não é instantânea.
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.lg),
            Text('Preparando a conexão segura…'),
          ],
        ),
      );
    }

    return PluggyConnectView(
      connectToken: token,
      updateItemId: widget.updateItemId,
      // Conectores de sandbox (Pluggy Bank) fora de produção: é o que permite
      // percorrer o fluxo inteiro sem banco real. Em produção seriam "bancos"
      // que não existem, oferecidos a quem quer conectar o dele.
      includeSandbox: !ref.watch(appEnvProvider).flavor.isProd,
      onEvent: _onConnectEvent,
    );
  }
}
