/// Monta a URL do widget Pluggy Connect.
///
/// O `connect_token` vai na query string porque é assim que o widget da Pluggy
/// recebe — o SDK JS deles faz igual. Não é escolha nossa, e é aceitável aqui:
/// a URL vive dentro de um WebView (não há barra de endereço nem histórico de
/// navegador do usuário), e o token vale 30 minutos com escopo restrito a ler o
/// item recém-criado.
library;

/// Host do widget. Constante porque `decideNavigation` só libera a Pluggy —
/// apontar para outro lugar exigiria mexer nas duas coisas, de propósito.
const _connectBaseUrl = 'https://connect.pluggy.ai';

/// Monta a URL do Connect.
///
/// [updateItemId] liga o modo de **atualização** de um item existente, que é o
/// caminho de re-consentimento. [includeSandbox] expõe os conectores de teste
/// (Pluggy Bank) — é o que permite exercitar o fluxo inteiro sem banco real.
String buildPluggyConnectUrl({
  required String connectToken,
  String? updateItemId,
  bool includeSandbox = false,
  String language = 'pt',
}) {
  // Parâmetro nulo ou vazio é **omitido**, não enviado vazio: `update_item=`
  // sem valor faria a Pluggy tratar como pedido de atualização de um item que
  // não existe.
  final parameters = <String, String>{
    'connect_token': connectToken,
    if (updateItemId != null && updateItemId.isNotEmpty)
      'update_item': updateItemId,
    'with_sandbox': includeSandbox.toString(),
    'lang': language,
  };

  return Uri.parse(
    _connectBaseUrl,
  ).replace(queryParameters: parameters).toString();
}
