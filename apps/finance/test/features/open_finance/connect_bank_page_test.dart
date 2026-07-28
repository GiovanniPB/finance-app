import 'package:core/core.dart';
import 'package:finance/features/open_finance/domain/open_finance_connection.dart';
import 'package:finance/features/open_finance/domain/open_finance_repository.dart';
import 'package:finance/features/open_finance/presentation/connect_bank_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Repositório que controla **quando** o token chega.
///
/// O caminho de sucesso não é exercitável aqui: com um token válido a tela
/// monta o `PluggyConnectView`, que instancia um `WebViewController` e exige a
/// implementação nativa da plataforma — inexistente num teste de widget. O que
/// se prova nestes testes é tudo o que acontece **antes** do WebView: espera,
/// falha, nova tentativa, e o pedido de re-consentimento.
class _ControlledRepository implements OpenFinanceRepository {
  _ControlledRepository({this.failure, this.hang = false});

  /// Quando presente, `requestConnectToken` falha com esta mensagem.
  final String? failure;

  /// Quando verdadeiro, o pedido nunca termina — o estado de espera.
  final bool hang;

  final List<String?> tokenRequests = [];

  @override
  Stream<List<OpenFinanceConnection>> watchAll() => Stream.value(const []);

  @override
  Future<Result<String, Failure>> requestConnectToken({
    String? updateItemId,
  }) {
    tokenRequests.add(updateItemId);
    if (hang) return Future.any([]);
    final message = failure;
    return Future.value(
      message == null
          // Um token qualquer nunca é devolvido nos testes de espera/falha;
          // devolvê-lo montaria o WebView.
          ? const Err(NetworkFailure('caminho não exercitado'))
          : Err(NetworkFailure(message)),
    );
  }

  @override
  Future<Result<OpenFinanceConnection, Failure>> save({
    required String itemId,
    int? connectorId,
    String? connectorName,
  }) async => Ok(testConnection(itemId: itemId));

  @override
  Future<Result<void, Failure>> revokeAccess(String connectionId) async =>
      const Ok(null);

  @override
  Future<Result<void, Failure>> delete(String id) async => const Ok(null);
}

void main() {
  group('ConnectBankPage', () {
    testWidgets('enquanto pede o token, diz o que está acontecendo', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ConnectBankPage(),
        openFinanceRepository: _ControlledRepository(hang: true),
        wrapInScaffold: false,
        // A tela mostra um indicador de progresso: `pumpAndSettle` nunca
        // convergiria.
        settle: false,
      );

      // Spinner sem texto leria como tela travada — pedir o token é ida à rede.
      expect(find.text('Preparando a conexão segura…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a falha aparece com a frase do repositório', (tester) async {
      await pumpScreen(
        tester,
        const ConnectBankPage(),
        openFinanceRepository: _ControlledRepository(
          failure: 'Sem conexão com o servidor.',
        ),
        wrapInScaffold: false,
      );

      expect(find.byKey(const Key('connect_error')), findsOneWidget);
      // A frase vem pronta em português — a Edge Function escreve `{"error"}`
      // para a tela, e o repository traduz o que ela não previu.
      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('"Tentar de novo" pede o token outra vez', (tester) async {
      final repo = _ControlledRepository(failure: 'Falhou.');
      await pumpScreen(
        tester,
        const ConnectBankPage(),
        openFinanceRepository: repo,
        wrapInScaffold: false,
      );

      expect(repo.tokenRequests, hasLength(1));

      await tapVisible(tester, find.text('Tentar de novo'));

      // Sem isto, a única saída de uma falha de rede seria fechar e reabrir.
      expect(repo.tokenRequests, hasLength(2));
    });

    testWidgets('conexão nova não manda itemId', (tester) async {
      final repo = _ControlledRepository(failure: 'x');
      await pumpScreen(
        tester,
        const ConnectBankPage(),
        openFinanceRepository: repo,
        wrapInScaffold: false,
      );

      expect(repo.tokenRequests.single, isNull);
    });

    testWidgets('re-consentimento manda o itemId e muda o título', (
      tester,
    ) async {
      final repo = _ControlledRepository(failure: 'x');
      await pumpScreen(
        tester,
        const ConnectBankPage(updateItemId: 'item-77'),
        openFinanceRepository: repo,
        wrapInScaffold: false,
      );

      // Sem `itemId` a Pluggy bloqueia a atualização via widget por segurança.
      expect(repo.tokenRequests.single, 'item-77');
      // O título diz qual dos dois fluxos é: "Conectar" cria, "Reconectar"
      // recupera algo que já existia.
      expect(find.text('Reconectar banco'), findsOneWidget);
    });

    testWidgets('conexão nova se chama Conectar banco', (tester) async {
      await pumpScreen(
        tester,
        const ConnectBankPage(),
        openFinanceRepository: _ControlledRepository(failure: 'x'),
        wrapInScaffold: false,
      );

      expect(find.text('Conectar banco'), findsOneWidget);
    });
  });
}
