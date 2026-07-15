import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import 'schema.dart';

/// Encapsula o [PowerSyncDatabase] e o seu ciclo de vida (conectar após login,
/// limpar no logout). Mantém o resto do app livre do SDK do PowerSync.
class PowerSyncService {
  PowerSyncService(this.db, {AppLogger? logger})
    : _log = logger ?? AppLogger('PowerSyncService');

  /// Instância única do banco local. Repositories consultam via [db].
  final PowerSyncDatabase db;
  final AppLogger _log;

  /// Abre e inicializa o banco local com o [appSchema].
  static Future<PowerSyncService> open({
    required String path,
    AppLogger? logger,
  }) async {
    final db = PowerSyncDatabase(schema: appSchema, path: path);
    await db.initialize();
    return PowerSyncService(db, logger: logger);
  }

  /// Inicia a sincronização usando o [connector]. Chamar após autenticar.
  Future<void> connect(PowerSyncBackendConnector connector) async {
    _log.info('Conectando PowerSync…');
    await db.connect(connector: connector);
  }

  /// Encerra a sincronização e apaga os dados locais. Chamar no logout.
  Future<void> disconnectAndClear() async {
    _log.info('Desconectando PowerSync e limpando dados locais.');
    await db.disconnectAndClear();
  }

  /// Fecha o banco (encerramento do app).
  Future<void> close() => db.close();
}

/// Resolve o caminho do arquivo do banco local por plataforma.
///
/// Em web o caminho é apenas o nome (o PowerSync usa OPFS/IndexedDB); em
/// plataformas nativas usa o diretório de suporte do app.
Future<String> resolveDatabasePath({String fileName = 'finance.db'}) async {
  if (kIsWeb) return fileName;
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, fileName);
}
