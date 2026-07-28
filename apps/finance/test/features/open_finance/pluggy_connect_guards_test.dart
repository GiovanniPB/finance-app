import 'package:finance/features/open_finance/presentation/pluggy_connect/pluggy_connect_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideNavigation', () {
    test('libera os hosts do Connect', () {
      for (final url in [
        'https://connect.pluggy.ai',
        'https://connect.pluggy.ai/?connect_token=abc',
        'https://api.pluggy.ai/items',
        'https://algum-subdominio-novo.pluggy.ai/x',
      ]) {
        expect(
          decideNavigation(url),
          NavigationVerdict.allow,
          reason: url,
        );
      }
    });

    test('recusa host de fora da Pluggy', () {
      for (final url in [
        'https://banco-qualquer.com.br/oauth',
        'https://evil.example.com',
        // O salto para o banco acontece fora do WebView; dentro dele, não.
        'https://accounts.google.com',
      ]) {
        expect(decideNavigation(url), NavigationVerdict.block, reason: url);
      }
    });

    test('recusa http puro, mesmo em host da Pluggy', () {
      // Aceitar texto claro abriria espaço para downgrade.
      expect(
        decideNavigation('http://connect.pluggy.ai'),
        NavigationVerdict.block,
      );
    });

    test('recusa esquema que não é web e URL malformada', () {
      for (final url in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,<script>',
        'intent://x',
        'não é uma url',
        '',
      ]) {
        expect(decideNavigation(url), NavigationVerdict.block, reason: url);
      }
    });

    test('não se deixa enganar por host que apenas termina parecido', () {
      // `pluggy.ai.evil.com` termina com `.com`, e `naopluggy.ai` não é
      // subdomínio de `pluggy.ai` — o sufixo aceito começa com ponto.
      expect(
        decideNavigation('https://pluggy.ai.evil.com/x'),
        NavigationVerdict.block,
      );
      expect(
        decideNavigation('https://naopluggy.ai/x'),
        NavigationVerdict.block,
      );
    });

    test('host em maiúsculas continua liberado', () {
      expect(
        decideNavigation('https://CONNECT.PLUGGY.AI/'),
        NavigationVerdict.allow,
      );
    });
  });

  group('canOpenExternally', () {
    test('aceita HTTPS de qualquer banco — allowlist aqui é impossível', () {
      expect(canOpenExternally('https://banco.com.br/oauth?x=1'), isTrue);
      expect(canOpenExternally('https://sso.itau.com.br/login'), isTrue);
    });

    test('recusa o que não é HTTPS', () {
      for (final url in [
        'http://banco.com.br',
        'javascript:alert(document.cookie)',
        'file:///etc/passwd',
        'data:text/html,<script>x</script>',
        'intent://scan/#Intent;scheme=zxing;end',
        'itms-apps://apps.apple.com',
        '',
        'não é url',
      ]) {
        expect(canOpenExternally(url), isFalse, reason: url);
      }
    });

    test('recusa HTTPS sem host', () {
      expect(canOpenExternally('https://'), isFalse);
    });
  });

  group('pluggyBridgeScript', () {
    test('aponta o objeto do React Native para o canal do Flutter', () {
      // A página do Connect publica eventos em
      // `window.ReactNativeWebView.postMessage` — ela é escrita para React
      // Native WebView. Sem este shim a chamada morre sem erro: o usuário
      // atravessa o fluxo, vê "dados coletados com sucesso", e nada é gravado.
      // Aconteceu de verdade na primeira passagem no simulador.
      expect(pluggyBridgeScript, contains('window.ReactNativeWebView'));
      expect(pluggyBridgeScript, contains('postMessage'));
    });

    test('usa exatamente o nome do canal registrado', () {
      // Se os dois saírem de sincronia, o fluxo fica **mudo**: nenhuma
      // exceção, nenhum log, só silêncio. É por isso que esta asserção existe.
      expect(pluggyBridgeScript, contains('window.$pluggyChannelName'));
      expect(pluggyChannelName, 'pluggyConnectHandler');
    });

    test('é JavaScript de uma expressão só, sem depender de bundler', () {
      // Injeção acontece por `runJavaScript`, que avalia texto cru: qualquer
      // sintaxe de módulo (import/export) falharia em silêncio.
      expect(pluggyBridgeScript, isNot(contains('import ')));
      expect(pluggyBridgeScript, isNot(contains('export ')));
      expect(pluggyBridgeScript.trim(), isNotEmpty);
    });
  });

  group('parseMessageType', () {
    test('reconhece os três tipos do contrato da Pluggy', () {
      expect(parseMessageType('OAUTH_OPEN'), PluggyMessageType.oauthOpen);
      expect(parseMessageType('LINK_OPEN'), PluggyMessageType.linkOpen);
      expect(parseMessageType('LOCATION'), PluggyMessageType.location);
    });

    test('tipo desconhecido ou nulo vira unknown, não exceção', () {
      // Canal JS é entrada não confiável: um tipo novo (ou lixo) não pode
      // derrubar a tela nem ser confundido com um dos tratados.
      expect(parseMessageType('TIPO_NOVO'), PluggyMessageType.unknown);
      expect(parseMessageType(''), PluggyMessageType.unknown);
      expect(parseMessageType(null), PluggyMessageType.unknown);
      expect(parseMessageType('oauth_open'), PluggyMessageType.unknown);
    });
  });
}
