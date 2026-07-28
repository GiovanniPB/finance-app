import 'package:finance/features/open_finance/domain/open_finance_connection.dart';
import 'package:finance/features/open_finance/presentation/connection_tile.dart';
import 'package:finance/features/profile/presentation/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  group('seção de bancos conectados', () {
    testWidgets('sem conexão, convida a conectar e explica o sigilo', (
      tester,
    ) async {
      await pumpScreen(tester, const ProfilePage());
      await scrollTo(tester, find.byKey(const Key('no_connections')));

      expect(find.text('Nenhum banco conectado'), findsOneWidget);
      // A frase sobre credencial não é enfeite: é a pergunta que trava quem
      // hesita em conectar o banco, e o app de fato nunca as vê (ADR 0005).
      expect(find.textContaining('o app nunca as vê'), findsOneWidget);
      expect(find.byKey(const Key('connect_bank')), findsNothing);
    });

    testWidgets('lista a conexão com o estado e o que ela trouxe', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [testConnection(connectorName: 'Itaú')],
        ),
        accounts: [
          testAccount(id: 'a1', name: 'Corrente', connectionId: 'conn-1'),
          testAccount(id: 'a2', name: 'Cartão', connectionId: 'conn-1'),
        ],
      );
      await scrollTo(tester, find.byKey(const Key('connection_conn-1')));

      expect(find.text('Itaú'), findsOneWidget);
      // Estado e contagem na mesma linha: "o que este banco entregou?" é a
      // pergunta que se faz olhando a lista.
      expect(find.text('Conectado · 2 contas'), findsOneWidget);
    });

    testWidgets('conta no singular quando é uma só', (tester) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [testConnection()],
        ),
        accounts: [testAccount(id: 'a1', connectionId: 'conn-1')],
      );
      await scrollTo(tester, find.byKey(const Key('connection_conn-1')));

      expect(find.text('Conectado · 1 conta'), findsOneWidget);
    });

    testWidgets('conexão recém-criada não mostra "0 contas"', (tester) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [testConnection(status: ConnectionStatus.pending)],
        ),
      );
      await scrollTo(tester, find.byKey(const Key('connection_conn-1')));

      // "0 contas" leria como falha, quando a sincronização só está em curso —
      // e o rótulo do status já diz isso.
      expect(find.text('Sincronizando pela primeira vez'), findsOneWidget);
      expect(find.textContaining('0 conta'), findsNothing);
    });

    testWidgets('conta de conta manual não é contada na conexão', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [testConnection()],
        ),
        accounts: [
          testAccount(id: 'a1', connectionId: 'conn-1'),
          // Sem `connectionId`: digitada à mão, não veio do banco.
          testAccount(id: 'a2', name: 'Carteira'),
        ],
      );
      await scrollTo(tester, find.byKey(const Key('connection_conn-1')));

      expect(find.text('Conectado · 1 conta'), findsOneWidget);
    });

    testWidgets('só conexão que precisa de ação responde ao toque', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [
            testConnection(id: 'conn-ok'),
            testConnection(
              id: 'conn-erro',
              itemId: 'item-erro',
              status: ConnectionStatus.loginError,
            ),
          ],
        ),
      );
      await scrollTo(tester, find.byKey(const Key('connection_conn-erro')));

      final ok = tester.widget<ConnectionTile>(
        find.byKey(const Key('connection_conn-ok')),
      );
      final erro = tester.widget<ConnectionTile>(
        find.byKey(const Key('connection_conn-erro')),
      );

      // Um detalhe que só repetisse o que a linha já diz seria toque sem
      // resposta; o que a linha com problema abre é o re-consentimento.
      expect(ok.onTap, isNull);
      expect(erro.onTap, isNotNull);
    });

    testWidgets('a senha trocada aparece como frase, não como código', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [
            testConnection(status: ConnectionStatus.loginError),
          ],
        ),
      );
      await scrollTo(tester, find.byKey(const Key('connection_conn-1')));

      expect(find.text('A senha do banco mudou'), findsOneWidget);
      // Vocabulário da Pluggy não vaza para a tela.
      expect(find.textContaining('LOGIN_ERROR'), findsNothing);
    });

    testWidgets('status desconhecido não derruba a lista', (tester) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [
            testConnection(status: ConnectionStatus.unknown),
          ],
        ),
      );
      await scrollTo(tester, find.byKey(const Key('connection_conn-1')));

      // O servidor é quem escreve o status, e a tabela local é view — o `check`
      // do Postgres não vale nela. Um app antigo diante de um vocabulário novo
      // mostra "Sincronizando" em vez de estourar.
      expect(find.text('Sincronizando'), findsOneWidget);
    });

    testWidgets('conexão sem nome de instituição não fica em branco', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [testConnection(connectorName: null)],
        ),
      );
      await scrollTo(tester, find.byKey(const Key('connection_conn-1')));

      expect(find.text('Banco conectado'), findsOneWidget);
    });

    testWidgets('havendo conexão, a ação passa a ser conectar outro', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfilePage(),
        openFinanceRepository: FakeOpenFinanceRepository(
          connections: [testConnection()],
        ),
      );
      await scrollTo(tester, find.byKey(const Key('connect_bank')));

      expect(find.text('Conectar outro banco'), findsOneWidget);
      expect(find.byKey(const Key('no_connections')), findsNothing);
    });
  });
}
