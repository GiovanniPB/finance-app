import 'package:core/core.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Conecta o PowerSync ao Supabase:
///  - [fetchCredentials]: fornece o endpoint do PowerSync + o JWT da sessão.
///  - [uploadData]: drena a fila local de writes e reaplica no Supabase.
class SupabaseConnector extends PowerSyncBackendConnector {
  SupabaseConnector({
    required this.powerSyncUrl,
    SupabaseClient? client,
    AppLogger? logger,
  }) : _client = client ?? Supabase.instance.client,
       _log = logger ?? AppLogger('SupabaseConnector');

  /// Endpoint da instância PowerSync (ex.: https://xyz.powersync.journeyapps.com).
  final String powerSyncUrl;
  final SupabaseClient _client;
  final AppLogger _log;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;

    return PowerSyncCredentials(
      endpoint: powerSyncUrl,
      token: session.accessToken,
      userId: session.user.id,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) return;

    try {
      for (final entry in batch.crud) {
        final table = _client.from(entry.table);
        switch (entry.op) {
          case UpdateType.put:
            await table.upsert({...?entry.opData, 'id': entry.id});
          case UpdateType.patch:
            await table.update(entry.opData ?? const {}).eq('id', entry.id);
          case UpdateType.delete:
            await table.delete().eq('id', entry.id);
        }
      }
      await batch.complete();
    } on PostgrestException catch (e, st) {
      // Erro do servidor (RLS, constraint, validação): reenviar o mesmo write
      // falharia para sempre e travaria a fila. Descartamos o batch.
      _log.severe(
        'Write rejeitado pelo Supabase; descartando batch. ${e.message}',
        e,
        st,
      );
      await batch.complete();
    }
    // Demais erros (rede/socket) propagam: o PowerSync re-tenta com backoff.
  }
}
