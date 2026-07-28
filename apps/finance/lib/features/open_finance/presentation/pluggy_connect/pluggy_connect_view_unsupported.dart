import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'pluggy_connect_event.dart';

/// Versão de [PluggyConnectView] usada onde não há WebView — hoje, web.
///
/// Existe para o build web continuar de pé (ver o cabeçalho de
/// `pluggy_connect_view.dart`) e para dizer ao usuário o que está acontecendo.
/// Um `UnsupportedError` aqui viraria tela branca; o recurso não estar
/// disponível é informação, não defeito.
class PluggyConnectView extends StatelessWidget {
  const PluggyConnectView({
    required this.connectToken,
    this.updateItemId,
    this.includeSandbox = false,
    this.onEvent,
    super.key,
  });

  final String connectToken;
  final String? updateItemId;
  final bool includeSandbox;
  final ValueChanged<PluggyConnectEvent>? onEvent;

  @override
  Widget build(BuildContext context) => const Center(
    child: AppEmptyState(
      icon: Icons.phone_iphone,
      title: 'Conectar banco só no aplicativo',
      message:
          'A conexão com o seu banco acontece no app de celular ou no '
          'desktop. Abra o Finance por lá para conectar.',
    ),
  );
}
