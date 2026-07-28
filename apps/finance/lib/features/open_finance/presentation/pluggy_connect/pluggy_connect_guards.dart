/// Decisões de segurança do WebView do Pluggy Connect, como funções puras.
///
/// Por que existem separadas do widget: são as regras que o pacote oficial
/// `flutter_pluggy_connect` **não** tem, e regra de segurança sem teste é
/// intenção, não garantia. Aqui elas são exercitáveis sem WebView, sem device e
/// sem rede.
///
/// O que foi internalizado e por quê está no cabeçalho de
/// `pluggy_connect_view.dart`.
library;

/// Hosts que o WebView do Connect pode carregar.
///
/// Só a Pluggy: o widget é uma página deles, e o salto para o banco acontece
/// **fora** do WebView (a página pede `OAUTH_OPEN`/`LINK_OPEN` e o app abre no
/// navegador do sistema). Um banco navegando dentro do nosso WebView não é o
/// fluxo desenhado — se acontecer, é para aparecer no log e não passar calado.
const pluggyAllowedHosts = {
  'connect.pluggy.ai',
  'api.pluggy.ai',
  'cdn.pluggy.ai',
};

/// Sufixo de domínio aceito além da lista explícita, para subdomínio novo da
/// própria Pluggy não derrubar o fluxo numa mudança de infraestrutura deles.
const pluggyAllowedSuffix = '.pluggy.ai';

/// O que fazer com uma navegação que o WebView pediu.
enum NavigationVerdict {
  /// Host da Pluggy: segue.
  allow,

  /// Qualquer outro: recusa. Quem chama registra em log — recusar em silêncio
  /// produziria uma tela branca sem explicação, que é o pior dos dois mundos.
  block,
}

/// Decide se o WebView pode navegar para [url].
///
/// Recusa por padrão: URL malformada, esquema que não seja HTTPS, ou host fora
/// da Pluggy. `http` puro entra na recusa de propósito — o Connect é HTTPS, e
/// aceitar texto claro abriria espaço para downgrade.
NavigationVerdict decideNavigation(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return NavigationVerdict.block;
  }
  final host = uri.host.toLowerCase();
  if (pluggyAllowedHosts.contains(host) || host.endsWith(pluggyAllowedSuffix)) {
    return NavigationVerdict.allow;
  }
  return NavigationVerdict.block;
}

/// Decide se uma URL vinda de mensagem JS pode ser aberta **fora** do app.
///
/// Aqui não há como usar allowlist de host: o destino é o banco que o usuário
/// escolheu, e são centenas de instituições. O que se pode exigir — e o pacote
/// oficial não exige — é que seja **HTTPS de verdade**. Isso barra a classe de
/// abuso que importa: `javascript:`, `file:`, `intent:`, `data:` e afins
/// chegando pelo canal JS e sendo entregues ao sistema operacional.
bool canOpenExternally(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme != 'https') return false;
  if (uri.host.isEmpty) return false;
  return true;
}

/// Tipos de mensagem que a página do Connect posta no canal JS.
///
/// Contrato **interno** da Pluggy, não documentado publicamente — conhecido por
/// leitura do fonte do pacote oficial deles (3.0.1). Se um dia o fluxo parar de
/// funcionar sem nada nosso ter mudado, este é o primeiro lugar a suspeitar.
enum PluggyMessageType {
  /// Pede para abrir OAuth do banco fora do app.
  oauthOpen,

  /// Pede para abrir um link qualquer fora do app.
  linkOpen,

  /// Informa a URL atual da página, de onde se extrai o resultado do fluxo.
  location,

  /// Qualquer coisa que não reconhecemos: ignorada, nunca tratada como as
  /// outras. Mensagem desconhecida num canal JS é entrada não confiável.
  unknown,
}

/// Traduz o campo `type` da mensagem JS.
PluggyMessageType parseMessageType(String? type) => switch (type) {
  'OAUTH_OPEN' => PluggyMessageType.oauthOpen,
  'LINK_OPEN' => PluggyMessageType.linkOpen,
  'LOCATION' => PluggyMessageType.location,
  _ => PluggyMessageType.unknown,
};
