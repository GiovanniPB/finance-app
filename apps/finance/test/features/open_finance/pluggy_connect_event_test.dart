import 'package:finance/features/open_finance/presentation/pluggy_connect/pluggy_connect_event.dart';
import 'package:finance/features/open_finance/presentation/pluggy_connect/pluggy_connect_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildPluggyConnectUrl', () {
    test('leva o token e os padrões', () {
      final url = Uri.parse(buildPluggyConnectUrl(connectToken: 'tok-123'));

      expect(url.host, 'connect.pluggy.ai');
      expect(url.scheme, 'https');
      expect(url.queryParameters['connect_token'], 'tok-123');
      expect(url.queryParameters['lang'], 'pt');
      expect(url.queryParameters['with_sandbox'], 'false');
    });

    test('omite update_item quando não há item a atualizar', () {
      final url = Uri.parse(buildPluggyConnectUrl(connectToken: 'tok'));

      // Mandar vazio faria a Pluggy tratar como atualização de um item que não
      // existe.
      expect(url.queryParameters.containsKey('update_item'), isFalse);
    });

    test('omite update_item também quando vem string vazia', () {
      final url = Uri.parse(
        buildPluggyConnectUrl(connectToken: 'tok', updateItemId: ''),
      );

      expect(url.queryParameters.containsKey('update_item'), isFalse);
    });

    test('modo de re-consentimento manda update_item', () {
      final url = Uri.parse(
        buildPluggyConnectUrl(connectToken: 'tok', updateItemId: 'item-9'),
      );

      expect(url.queryParameters['update_item'], 'item-9');
    });

    test('sandbox ligado expõe os conectores de teste', () {
      final url = Uri.parse(
        buildPluggyConnectUrl(connectToken: 'tok', includeSandbox: true),
      );

      expect(url.queryParameters['with_sandbox'], 'true');
    });

    test('a URL gerada é aceita pela guarda de navegação', () {
      // As duas coisas têm de concordar: de nada serve montar uma URL que o
      // próprio WebView recusaria carregar.
      final url = buildPluggyConnectUrl(connectToken: 'tok');
      expect(Uri.parse(url).host.endsWith('pluggy.ai'), isTrue);
    });
  });

  group('readPluggyLocation', () {
    test('SUCCESS com item_id produz conexão utilizável', () {
      final read = readPluggyLocation(
        '?events=SELECTED_INSTITUTION,LOGIN_SUCCESS,SUCCESS&item_id=item-42'
        '&timestamp=111&item_status=UPDATED&execution_status=SUCCESS'
        '&connector_id=201&connector_name=Ita%C3%BA',
      );

      final event = read.event;
      expect(event, isA<PluggyConnectSucceeded>());
      final success = event! as PluggyConnectSucceeded;
      expect(success.itemId, 'item-42');
      expect(success.itemStatus, 'UPDATED');
      expect(success.executionStatus, 'SUCCESS');
      expect(success.connectorId, 201);
      expect(success.connectorName, 'Itaú');
      expect(read.timestamp, '111');
    });

    test('o evento corrente é o último de events, não o primeiro', () {
      final read = readPluggyLocation(
        'events=OPEN,SELECTED_INSTITUTION&timestamp=1',
      );

      expect(read.event, isA<PluggyConnectProgress>());
      expect(
        (read.event! as PluggyConnectProgress).eventType,
        'SELECTED_INSTITUTION',
      );
    });

    test('SUCCESS sem item_id vira falha, não conexão órfã', () {
      final read = readPluggyLocation('events=SUCCESS&timestamp=2');

      // Sem item não há o que gravar em open_finance_connections; tratar como
      // sucesso criaria uma linha que não aponta para nada na Pluggy.
      expect(read.event, isA<PluggyConnectFailed>());
    });

    test('ERROR carrega a mensagem do fornecedor para log', () {
      final read = readPluggyLocation(
        'events=ERROR&error=LOGIN_ERROR&timestamp=3&item_id=item-1',
      );

      final failure = read.event! as PluggyConnectFailed;
      expect(failure.message, 'LOGIN_ERROR');
      expect(failure.itemId, 'item-1');
    });

    test('CLOSE é desistência, não erro', () {
      final read = readPluggyLocation('events=OPEN,CLOSE&timestamp=4');

      // Quem fechou o widget mudou de ideia; mostrar mensagem de falha para
      // isso seria inventar um problema.
      expect(read.event, isA<PluggyConnectClosed>());
    });

    test('timestamp repetido não emite evento de novo', () {
      final primeira = readPluggyLocation(
        'events=SUCCESS&item_id=i&timestamp=9',
      );
      expect(primeira.event, isA<PluggyConnectSucceeded>());

      final repetida = readPluggyLocation(
        'events=SUCCESS&item_id=i&timestamp=9',
        lastTimestamp: primeira.timestamp,
      );

      // A página reposta a mesma localização várias vezes; sem esta guarda, a
      // conexão seria gravada em duplicidade.
      expect(repetida.event, isNull);
      expect(repetida.timestamp, '9');
    });

    test('timestamp novo com o mesmo evento emite de novo', () {
      final read = readPluggyLocation(
        'events=LOGIN_SUCCESS&timestamp=10',
        lastTimestamp: '9',
      );

      expect(read.event, isA<PluggyConnectProgress>());
    });

    test('mensagem sem events não produz evento', () {
      expect(readPluggyLocation('timestamp=5').event, isNull);
      expect(readPluggyLocation('events=&timestamp=5').event, isNull);
      expect(readPluggyLocation('').event, isNull);
    });

    test('aceita a URL inteira, não só a query', () {
      final read = readPluggyLocation(
        'https://connect.pluggy.ai/?events=SUCCESS&item_id=x&timestamp=7',
      );

      expect(read.event, isA<PluggyConnectSucceeded>());
    });

    test('query malformada não derruba a tela', () {
      // Canal JS é entrada não confiável.
      for (final raw in ['%%%', '?%zz=1', 'events=SUCCESS&item_id=%']) {
        expect(() => readPluggyLocation(raw), returnsNormally, reason: raw);
      }
    });

    test('connector_id não numérico não estoura', () {
      final read = readPluggyLocation(
        'events=SELECTED_INSTITUTION&connector_id=abc&timestamp=8',
      );

      expect((read.event! as PluggyConnectProgress).connectorId, isNull);
    });
  });
}
