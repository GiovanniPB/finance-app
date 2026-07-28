/// O widget Pluggy Connect, escolhido por plataforma em tempo de compilação.
///
/// **Por que export condicional.** `webview_flutter` suporta android, iOS e
/// macOS — **não** web. O CI deste repo compila `main_dev.dart` para web (job
/// "Build smoke (web)"), e o compilador Dart puxa todo o grafo alcançável: sem
/// esta divisão, adicionar a tela de conexão bancária derrubaria um gate de CI
/// que não tem nada a ver com Open Finance.
///
/// Em web entra o stub, que diz que o recurso não existe ali em vez de falhar
/// com tela branca. É coerente com o posicionamento do produto — mobile e
/// desktop primeiro, web secundário — e com o fato de que conectar banco por
/// Open Finance num navegador não é um caminho que este app oferece.
library;

export 'pluggy_connect_view_unsupported.dart'
    if (dart.library.io) 'pluggy_connect_view_native.dart';
