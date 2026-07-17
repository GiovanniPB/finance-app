import 'dart:async';

import 'package:core/core.dart';
import 'package:database/database.dart';
import 'package:powersync/powersync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../di/providers.dart';
import '../auth/domain/auth_repository.dart';
import '../auth/presentation/auth_providers.dart';

part 'sync_coordinator.g.dart';

/// Liga o ciclo de vida do PowerSync ao estado de autenticação: conecta a
/// sincronização quando há usuário e limpa os dados locais no logout.
///
/// A lógica de transição é isolada aqui (testável) — o disparo a partir do
/// stream de auth fica no [syncCoordinatorProvider].
class SyncCoordinator {
  SyncCoordinator({
    required this.service,
    required this.connector,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger('SyncCoordinator');

  final PowerSyncService service;
  final PowerSyncBackendConnector connector;
  final AppLogger _log;

  bool _connected = false;

  /// `true` quando a sincronização está ativa (exposto para testes/observação).
  bool get isConnected => _connected;

  /// Reage a uma mudança de sessão. Idempotente: conectar/desconectar só
  /// ocorre na transição (evita reconectar a cada refresh de token).
  Future<void> onAuthChanged(AuthUser? user) async {
    if (user != null && !_connected) {
      _connected = true;
      _log.info('Usuário autenticado — conectando sincronização.');
      await service.connect(connector);
    } else if (user == null && _connected) {
      _connected = false;
      _log.info('Logout — desconectando e limpando dados locais.');
      await service.disconnectAndClear();
    }
  }
}

/// Instancia o [SyncCoordinator] e o assina ao stream de auth. keepAlive para
/// viver por toda a sessão do app. Ativado uma vez no bootstrap.
@Riverpod(keepAlive: true)
SyncCoordinator syncCoordinator(Ref ref) {
  final coordinator = SyncCoordinator(
    service: ref.watch(powerSyncServiceProvider),
    connector: ref.watch(supabaseConnectorProvider),
  );
  ref.listen(authStateProvider, (previous, next) {
    unawaited(coordinator.onAuthChanged(next.asData?.value));
  }, fireImmediately: true);
  return coordinator;
}
