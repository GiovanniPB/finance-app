import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/open_finance_connection.dart';
import '../domain/open_finance_repository.dart';

/// Statements de conexão, em constantes para o teste de guarda rodá-las contra
/// uma view igual à que o PowerSync cria.
///
/// As tabelas locais do PowerSync são **views com triggers `INSTEAD OF`**, e o
/// SQLite recusa construções que uma tabela aceitaria — foi assim que o UPSERT
/// de orçamento passou meses quebrado com o teste verde.
abstract final class OpenFinanceSql {
  static const watchAll =
      'SELECT * FROM open_finance_connections WHERE owner_id = ? '
      'ORDER BY created_at DESC';

  /// Nenhum `ON CONFLICT` aqui, mesmo havendo `unique (item_id)` no Postgres:
  /// view não aceita UPSERT. Reconectar o mesmo banco é evitado antes, pelo
  /// `avoidDuplicates` do Connect Token — e se ainda assim colidir, quem recusa
  /// é o Postgres na subida, não o cliente.
  static const insert =
      'INSERT INTO open_finance_connections (id, owner_id, item_id, '
      'connector_id, connector_name, status, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)';

  static const deleteById = 'DELETE FROM open_finance_connections WHERE id = ?';

  /// Já existe conexão para este `item_id`? Select-then-write, porque o widget
  /// pode devolver `SUCCESS` mais de uma vez para o mesmo item.
  static const findByItemId =
      'SELECT * FROM open_finance_connections WHERE item_id = ? LIMIT 1';
}

/// Implementação sobre o PowerSync (SQL bruto) mais uma chamada de rede à nossa
/// Edge Function. Depende de [SqliteConnection] para permitir teste com mocks.
class OpenFinanceRepositoryImpl implements OpenFinanceRepository {
  OpenFinanceRepositoryImpl({
    required this.db,
    required this.supabase,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('OpenFinanceRepository');

  /// Nome da Edge Function que emite o Connect Token.
  static const connectTokenFunction = 'pluggy-connect-token';

  final SqliteConnection db;
  final SupabaseClient supabase;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  @override
  Stream<List<OpenFinanceConnection>> watchAll() {
    final userId = supabase.auth.currentUser?.id;
    // Sem sessão não há conexão a exibir; evita vazar o banco local inteiro.
    if (userId == null) return Stream.value(const []);

    return db
        .watch(OpenFinanceSql.watchAll, parameters: [userId])
        .map((rows) => rows.map(OpenFinanceConnection.fromRow).toList());
  }

  @override
  Future<Result<String, Failure>> requestConnectToken({
    String? updateItemId,
  }) async {
    if (supabase.auth.currentUser == null) {
      return const Err(
        AuthFailure('Entre na sua conta para conectar um banco.'),
      );
    }

    try {
      final response = await supabase.functions.invoke(
        connectTokenFunction,
        // Corpo só no re-consentimento: a função trata ausência de body.
        body: updateItemId == null ? null : {'itemId': updateItemId},
      );

      final data = response.data;
      final token = data is Map ? data['accessToken'] : null;
      if (token is! String || token.isEmpty) {
        _log.warning(
          'Edge Function respondeu sem accessToken '
          '(status ${response.status})',
        );
        return const Err(
          NetworkFailure(
            'Não foi possível iniciar a conexão com o banco. '
            'Tente de novo em instantes.',
          ),
        );
      }
      return Ok(token);
    } on FunctionException catch (e, st) {
      // A função devolve `{"error": "<frase em português>"}` nas falhas que ela
      // mesma prevê. Quando houver essa frase, ela é melhor que qualquer coisa
      // genérica — foi escrita para a tela. Nos outros casos o detalhe é do
      // fornecedor e fica só no log.
      _log.warning('Edge Function de Connect Token falhou', e, st);
      final details = e.details;
      final message = details is Map ? details['error'] : null;
      return Err(
        NetworkFailure(
          message is String && message.isNotEmpty
              ? message
              : 'Não foi possível iniciar a conexão com o banco. '
                    'Tente de novo em instantes.',
        ),
      );
    } on Exception catch (e, st) {
      // `FunctionException` cobre a falha que a função *reporta*; sem internet,
      // ou com DNS fora, `invoke` lança outra coisa antes de haver resposta.
      // Sem este ramo a exceção subiria crua para a tela.
      _log.warning('Falha de rede ao pedir Connect Token', e, st);
      return const Err(
        NetworkFailure(
          'Sem conexão com o servidor. '
          'Verifique sua internet e tente de novo.',
        ),
      );
    }
  }

  @override
  Future<Result<OpenFinanceConnection, Failure>> save({
    required String itemId,
    int? connectorId,
    String? connectorName,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(
        AuthFailure('Nenhuma sessão ativa para salvar a conexão.'),
      );
    }
    if (itemId.trim().isEmpty) {
      return const Err(
        ValidationFailure('A conexão veio sem identificador do provedor.'),
      );
    }

    try {
      // O widget pode emitir `SUCCESS` mais de uma vez para o mesmo item (a
      // página reposta a localização). Sem esta checagem, o segundo `SUCCESS`
      // criaria uma segunda linha local que o Postgres depois recusaria pela
      // `unique (item_id)` — falha de upload silenciosa, longe da causa.
      final existing = await db.getOptional(OpenFinanceSql.findByItemId, [
        itemId.trim(),
      ]);
      if (existing != null) {
        return Ok(OpenFinanceConnection.fromRow(existing));
      }

      final timestamp = _now();
      final connection = OpenFinanceConnection(
        id: _genId(),
        ownerId: userId,
        itemId: itemId.trim(),
        // Nasce `pending`: o login passou, mas a primeira sincronização segue
        // em curso do lado da Pluggy. Dizer "Conectado" aqui prometeria dado
        // que ainda não chegou.
        status: ConnectionStatus.pending,
        createdAt: timestamp,
        updatedAt: timestamp,
        connectorId: connectorId,
        connectorName: _blankToNull(connectorName),
      );

      await db.execute(OpenFinanceSql.insert, [
        connection.id,
        connection.ownerId,
        connection.itemId,
        connection.connectorId,
        connection.connectorName,
        connection.status.db,
        connection.createdAt.toIso8601String(),
        connection.updatedAt.toIso8601String(),
      ]);

      return Ok(connection);
    } on Exception catch (e, st) {
      _log.severe('Falha ao salvar conexão de Open Finance', e, st);
      return const Err(
        DatabaseFailure('Não foi possível salvar a conexão com o banco.'),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      await db.execute(OpenFinanceSql.deleteById, [id]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover conexão de Open Finance', e, st);
      return const Err(
        DatabaseFailure('Não foi possível remover a conexão.'),
      );
    }
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
