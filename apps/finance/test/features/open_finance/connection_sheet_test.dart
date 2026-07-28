import 'package:core/core.dart';
import 'package:finance/features/open_finance/domain/open_finance_connection.dart';
import 'package:finance/features/open_finance/presentation/connection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Abre a folha de ações de uma conexão.
///
/// Vai por um botão em vez de chamar `ConnectionSheet.show` direto porque a
/// folha usa `Navigator.pop` para se fechar, e sem uma rota abaixo dela o pop
/// desmontaria a árvore do teste.
Future<void> pumpSheet(
  WidgetTester tester, {
  required OpenFinanceConnection connection,
  int accountCount = 2,
  FakeOpenFinanceRepository? repository,
}) async {
  final repo =
      repository ?? FakeOpenFinanceRepository(connections: [connection]);

  await pumpScreen(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => ConnectionSheet.show(
          context,
          connection: connection,
          accountCount: accountCount,
        ),
        child: const Text('abrir'),
      ),
    ),
    openFinanceRepository: repo,
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('ConnectionSheet', () {
    testWidgets('mostra o nome, o estado e quantas contas a conexão trouxe', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        connection: testConnection(connectorName: 'Nubank'),
      );

      expect(find.text('Nubank'), findsOneWidget);
      expect(find.textContaining('2 contas'), findsOneWidget);
    });

    testWidgets('conexão saudável abre a folha e oferece remover — antes ela '
        'não respondia ao toque, e "Remover banco" não existia em tela '
        'nenhuma', (tester) async {
      await pumpSheet(
        tester,
        connection: testConnection(),
      );

      expect(find.byKey(const Key('connection_remove')), findsOneWidget);
      // Reconectar é só para quem precisa: oferecê-lo numa conexão saudável
      // convidaria a refazer um consentimento que está valendo.
      expect(find.byKey(const Key('connection_reconnect')), findsNothing);
    });

    testWidgets('conexão que pede ação oferece reconectar', (tester) async {
      await pumpSheet(
        tester,
        connection: testConnection(status: ConnectionStatus.consentExpired),
      );

      expect(find.byKey(const Key('connection_reconnect')), findsOneWidget);
    });

    testWidgets('a confirmação diz que o acesso é cancelado no banco e que o '
        'histórico fica', (tester) async {
      await pumpSheet(tester, connection: testConnection());

      await tester.tap(find.byKey(const Key('connection_remove')));
      await tester.pumpAndSettle();

      expect(find.textContaining('cancelado no banco'), findsOneWidget);
      expect(find.textContaining('continuam aqui'), findsOneWidget);
    });

    testWidgets('cancelar na confirmação não revoga nem apaga', (tester) async {
      final repo = FakeOpenFinanceRepository(connections: [testConnection()]);
      await pumpSheet(
        tester,
        connection: testConnection(),
        repository: repo,
      );

      await tester.tap(find.byKey(const Key('connection_remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.revoked, isEmpty);
      expect(repo.deleted, isEmpty);
    });

    testWidgets('confirmar revoga o acesso e só então apaga a linha', (
      tester,
    ) async {
      final connection = testConnection();
      final repo = FakeOpenFinanceRepository(connections: [connection]);
      await pumpSheet(tester, connection: connection, repository: repo);

      await tester.tap(find.byKey(const Key('connection_remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_remove_connection')));
      await tester.pumpAndSettle();

      expect(repo.revoked, [connection.id]);
      expect(repo.deleted, [connection.id]);
    });

    testWidgets(
      'revogação que falha NÃO apaga a linha — apagar deixaria o '
      'consentimento vivo no banco sem nada apontando para ele',
      (tester) async {
        final connection = testConnection();
        final repo = FakeOpenFinanceRepository(connections: [connection])
          ..revokeFailure = const NetworkFailure('Sem conexão com o servidor.');

        await pumpSheet(tester, connection: connection, repository: repo);

        await tester.tap(find.byKey(const Key('connection_remove')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_remove_connection')));
        await tester.pumpAndSettle();

        expect(repo.deleted, isEmpty);
        expect(
          find.byKey(const Key('connection_remove_error')),
          findsOneWidget,
        );
        // A folha fica aberta: fechá-la com erro esconderia a única frase que
        // diz o que fazer.
        expect(find.byKey(const Key('connection_remove')), findsOneWidget);
      },
    );

    testWidgets('funciona no tema escuro', (tester) async {
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => ConnectionSheet.show(
              context,
              connection: testConnection(),
              accountCount: 1,
            ),
            child: const Text('abrir'),
          ),
        ),
        dark: true,
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('connection_remove')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
