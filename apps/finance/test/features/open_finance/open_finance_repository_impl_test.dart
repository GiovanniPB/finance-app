import 'package:core/core.dart';
import 'package:finance/features/open_finance/data/open_finance_repository_impl.dart';
import 'package:finance/features/open_finance/domain/open_finance_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

/// `getOptional` devolve `Row` (tipo do sqlite3), não um `Map` — então a linha
/// falsa precisa nascer de um `ResultSet` de verdade.
Row rowFrom(Map<String, Object?> values) =>
    ResultSet(values.keys.toList(), const [], [
      values.values.toList(),
    ]).first;

void main() {
  setUpAll(() {
    registerFallbackValue(<Object?>[]);
    registerFallbackValue(HttpMethod.post);
  });

  late MockSqliteConnection db;
  late MockSupabaseClient supabase;
  late MockGoTrueClient auth;
  late MockFunctionsClient functions;

  OpenFinanceRepositoryImpl buildRepo() => OpenFinanceRepositoryImpl(
    db: db,
    supabase: supabase,
    now: () => DateTime.utc(2026, 7, 28, 12),
    genId: () => 'conn-1',
  );

  void signedIn({String id = 'user-1'}) {
    final user = MockUser();
    when(() => user.id).thenReturn(id);
    when(() => auth.currentUser).thenReturn(user);
  }

  setUp(() {
    db = MockSqliteConnection();
    supabase = MockSupabaseClient();
    auth = MockGoTrueClient();
    functions = MockFunctionsClient();
    when(() => supabase.auth).thenReturn(auth);
    when(() => supabase.functions).thenReturn(functions);
    when(() => auth.currentUser).thenReturn(null);
  });

  group('watchAll', () {
    test('sem sessão devolve lista vazia, sem tocar o banco', () async {
      final connections = await buildRepo().watchAll().first;

      expect(connections, isEmpty);
      // Consultar sem filtro de dono vazaria o banco local inteiro.
      verifyNever(() => db.watch(any(), parameters: any(named: 'parameters')));
    });

    test('filtra pelo dono da sessão', () async {
      signedIn(id: 'user-42');
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(emptyResultSet()));

      await buildRepo().watchAll().first;

      final captured = verify(
        () => db.watch(
          captureAny(),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      expect(captured[0], contains('owner_id = ?'));
      expect(captured[1], ['user-42']);
    });
  });

  group('requestConnectToken', () {
    test('sem sessão nem tenta a rede', () async {
      final result = await buildRepo().requestConnectToken();

      expect(result.failureOrNull, isA<AuthFailure>());
      verifyNever(() => functions.invoke(any()));
    });

    test('devolve o accessToken da Edge Function', () async {
      signedIn();
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => const FunctionResponse(
          data: {'accessToken': 'token-abc'},
          status: 200,
        ),
      );

      final result = await buildRepo().requestConnectToken();

      expect(result.valueOrNull, 'token-abc');
    });

    test('não manda body quando não é re-consentimento', () async {
      signedIn();
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
        (_) async =>
            const FunctionResponse(data: {'accessToken': 't'}, status: 200),
      );

      await buildRepo().requestConnectToken();

      final captured = verify(
        () => functions.invoke(
          OpenFinanceRepositoryImpl.connectTokenFunction,
          body: captureAny(named: 'body'),
        ),
      ).captured;
      // Body vazio distingue "conectar novo" de "atualizar item existente" — a
      // Pluggy bloqueia atualização sem `itemId`.
      expect(captured.single, isNull);
    });

    test('re-consentimento manda o itemId no body', () async {
      signedIn();
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
        (_) async =>
            const FunctionResponse(data: {'accessToken': 't'}, status: 200),
      );

      await buildRepo().requestConnectToken(updateItemId: 'item-9');

      final captured = verify(
        () => functions.invoke(any(), body: captureAny(named: 'body')),
      ).captured;
      expect(captured.single, {'itemId': 'item-9'});
    });

    test('resposta sem accessToken vira NetworkFailure', () async {
      signedIn();
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
        (_) async =>
            const FunctionResponse(data: {'algo': 'outro'}, status: 200),
      );

      final result = await buildRepo().requestConnectToken();

      expect(result.failureOrNull, isA<NetworkFailure>());
    });

    test('a frase que a função escreveu chega à tela', () async {
      signedIn();
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenThrow(
        const FunctionException(
          status: 404,
          details: {'error': 'Essa conexão não foi encontrada no provedor.'},
        ),
      );

      final result = await buildRepo().requestConnectToken(
        updateItemId: 'item-inexistente',
      );

      // A Edge Function escreve `{"error": "..."}` em português justamente para
      // a tela; descartá-la por uma genérica perderia a informação melhor.
      expect(
        result.failureOrNull?.message,
        'Essa conexão não foi encontrada no provedor.',
      );
    });

    test('falha sem frase própria cai numa genérica em português', () async {
      signedIn();
      when(
        () => functions.invoke(any(), body: any(named: 'body')),
      ).thenThrow(const FunctionException(status: 500));

      final result = await buildRepo().requestConnectToken();

      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(result.failureOrNull?.message, contains('Não foi possível'));
    });

    test('erro de rede antes da resposta também é tratado', () async {
      signedIn();
      // Sem internet, `invoke` lança antes de existir `FunctionException`.
      when(
        () => functions.invoke(any(), body: any(named: 'body')),
      ).thenThrow(const SocketExceptionStub());

      final result = await buildRepo().requestConnectToken();

      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(result.failureOrNull?.message, contains('conexão'));
    });
  });

  group('revokeAccess', () {
    test('sem sessão não chama a função', () async {
      final result = await buildRepo().revokeAccess('conn-1');

      expect(result.failureOrNull, isA<AuthFailure>());
      verifyNever(() => functions.invoke(any(), body: any(named: 'body')));
    });

    test('manda o id da conexão, não o do item — quem resolve o item é o '
        'servidor, pela RLS', () async {
      signedIn();
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
        (_) async =>
            const FunctionResponse(data: {'revoked': true}, status: 200),
      );

      final result = await buildRepo().revokeAccess('conn-42');

      expect(result.isOk, isTrue);
      final captured = verify(
        () => functions.invoke(captureAny(), body: captureAny(named: 'body')),
      ).captured;
      expect(captured[0], 'pluggy-disconnect');
      expect(captured[1], {'connectionId': 'conn-42'});
    });

    test('a frase que a função escreveu chega à tela', () async {
      signedIn();
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenThrow(
        const FunctionException(
          status: 404,
          details: {'error': 'Essa conexão não existe mais.'},
        ),
      );

      final result = await buildRepo().revokeAccess('conn-1');

      expect(
        result.failureOrNull?.message,
        'Essa conexão não existe mais.',
      );
    });

    test('sem internet o erro diz que revogar precisa dela', () async {
      signedIn();
      when(
        () => functions.invoke(any(), body: any(named: 'body')),
      ).thenThrow(Exception('socket'));

      final result = await buildRepo().revokeAccess('conn-1');

      // Revogação é inerentemente online: prometer fila offline aqui deixaria o
      // usuário achando que cancelou um acesso que segue valendo.
      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(result.failureOrNull?.message, contains('internet'));
    });
  });

  group('save', () {
    test('sem sessão devolve AuthFailure', () async {
      final result = await buildRepo().save(itemId: 'item-1');

      expect(result.failureOrNull, isA<AuthFailure>());
    });

    test('itemId vazio é recusado antes de tocar o banco', () async {
      signedIn();

      final result = await buildRepo().save(itemId: '   ');

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(any(), any()));
    });

    test('grava a conexão como pending', () async {
      signedIn(id: 'user-7');
      when(() => db.getOptional(any(), any())).thenAnswer((_) async => null);
      when(() => db.execute(any(), any())).thenAnswer(
        (_) async => emptyResultSet(),
      );

      final result = await buildRepo().save(
        itemId: 'item-abc',
        connectorId: 201,
        connectorName: 'Itaú',
      );

      final connection = result.valueOrNull!;
      expect(connection.id, 'conn-1');
      expect(connection.ownerId, 'user-7');
      expect(connection.itemId, 'item-abc');
      expect(connection.connectorName, 'Itaú');
      // O login passou, mas a primeira sincronização da Pluggy segue em curso:
      // dizer "Conectado" aqui prometeria dado que ainda não chegou.
      expect(connection.status, ConnectionStatus.pending);
    });

    test('o SQL de insert não usa UPSERT — view do PowerSync recusa', () {
      // Guarda da lição do orçamento: `ON CONFLICT` passava no mock e falhava
      // no SQLite de verdade.
      expect(OpenFinanceSql.insert.toUpperCase(), isNot(contains('CONFLICT')));
    });

    test(
      'item já conhecido devolve a conexão existente, sem duplicar',
      () async {
        signedIn();
        when(() => db.getOptional(any(), any())).thenAnswer(
          (_) async => rowFrom({
            'id': 'conn-existente',
            'owner_id': 'user-1',
            'item_id': 'item-abc',
            'status': 'active',
            'created_at': '2026-07-01T00:00:00.000Z',
            'updated_at': '2026-07-01T00:00:00.000Z',
          }),
        );

        final result = await buildRepo().save(itemId: 'item-abc');

        expect(result.valueOrNull?.id, 'conn-existente');
        // O widget reposta `SUCCESS` mais de uma vez; um segundo INSERT criaria
        // linha local que o Postgres recusaria depois pela unique — falha de
        // upload silenciosa, longe da causa.
        verifyNever(() => db.execute(any(), any()));
      },
    );

    test('nome em branco não vira string vazia no banco', () async {
      signedIn();
      when(() => db.getOptional(any(), any())).thenAnswer((_) async => null);
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final result = await buildRepo().save(itemId: 'i', connectorName: '  ');

      expect(result.valueOrNull?.connectorName, isNull);
    });
  });

  group('delete', () {
    test('remove pelo id', () async {
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());

      final result = await buildRepo().delete('conn-1');

      expect(result.isOk, isTrue);
      final captured = verify(
        () => db.execute(captureAny(), captureAny()),
      ).captured;
      expect(captured[0], contains('DELETE FROM open_finance_connections'));
      expect(captured[1], ['conn-1']);
    });
  });
}

/// Exceção de rede para o teste, no lugar de `SocketException` (que exige
/// `dart:io` e não compilaria na suíte de web).
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
