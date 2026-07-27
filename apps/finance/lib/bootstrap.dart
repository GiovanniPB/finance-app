import 'dart:async';

import 'package:core/core.dart';
import 'package:database/database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'di/providers.dart';
import 'features/onboarding/data/onboarding_store.dart';
import 'features/onboarding/presentation/onboarding_providers.dart';
import 'features/sync/sync_coordinator.dart';

/// Ponto de entrada comum a todos os flavors. Inicializa serviços, abre o banco
/// local e injeta as instâncias prontas na árvore de providers.
Future<void> bootstrap(AppEnv env) async {
  AppLogger.configure(level: env.flavor.isProd ? Level.WARNING : Level.ALL);
  final log = AppLogger('bootstrap');

  await runZonedGuarded(
    () async {
      // Inicializa as bindings DENTRO da mesma zona do runApp: com
      // runZonedGuarded, inicializá-las na zona raiz causa "Zone mismatch".
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) =>
          log.severe('FlutterError', details.exception, details.stack);

      await Supabase.initialize(
        url: env.supabaseUrl,
        publishableKey: env.supabaseAnonKey,
      );

      final dbPath = await resolveDatabasePath();
      final powerSync = await PowerSyncService.open(path: dbPath);
      final connector = SupabaseConnector(powerSyncUrl: env.powersyncUrl);

      // Lido aqui, e não num provider assíncrono, para o guard de rota decidir
      // no primeiro frame se mostra a apresentação (ver onboarding_providers).
      final seenOnboarding = await OnboardingStore(db: powerSync.db).hasSeen();

      // Ativa o ciclo de vida do sync via cascade: conecta o PowerSync ao
      // autenticar e limpa os dados locais no logout (reage ao stream de auth).
      final container = ProviderContainer(
        overrides: [
          appEnvProvider.overrideWithValue(env),
          powerSyncServiceProvider.overrideWithValue(powerSync),
          supabaseConnectorProvider.overrideWithValue(connector),
          onboardingSeenAtBootProvider.overrideWithValue(seenOnboarding),
        ],
      )..read(syncCoordinatorProvider);

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const FinanceApp(),
        ),
      );
    },
    (error, stack) => log.severe('Uncaught zone error', error, stack),
  );
}
