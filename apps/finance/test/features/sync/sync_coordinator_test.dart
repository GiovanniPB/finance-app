import 'package:database/database.dart';
import 'package:finance/features/auth/domain/auth_repository.dart';
import 'package:finance/features/sync/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:powersync/powersync.dart';

class MockPowerSyncService extends Mock implements PowerSyncService {}

class FakeConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => null;

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}

void main() {
  late MockPowerSyncService service;
  late FakeConnector connector;
  late SyncCoordinator coordinator;

  setUp(() {
    service = MockPowerSyncService();
    connector = FakeConnector();
    coordinator = SyncCoordinator(service: service, connector: connector);
    when(() => service.connect(connector)).thenAnswer((_) async {});
    when(() => service.disconnectAndClear()).thenAnswer((_) async {});
  });

  const user = AuthUser(id: 'user-1');

  test('conecta a sincronização ao autenticar', () async {
    await coordinator.onAuthChanged(user);

    expect(coordinator.isConnected, isTrue);
    verify(() => service.connect(connector)).called(1);
  });

  test('não reconecta em emissões repetidas de auth', () async {
    await coordinator.onAuthChanged(user);
    await coordinator.onAuthChanged(user);

    verify(() => service.connect(connector)).called(1);
    verifyNever(() => service.disconnectAndClear());
  });

  test('desconecta e limpa dados locais no logout', () async {
    await coordinator.onAuthChanged(user);
    await coordinator.onAuthChanged(null);

    expect(coordinator.isConnected, isFalse);
    verify(() => service.disconnectAndClear()).called(1);
  });

  test('ignora null inicial quando nunca conectou', () async {
    await coordinator.onAuthChanged(null);

    expect(coordinator.isConnected, isFalse);
    verifyNever(() => service.connect(connector));
    verifyNever(() => service.disconnectAndClear());
  });
}
