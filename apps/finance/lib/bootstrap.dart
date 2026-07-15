import 'dart:async';

import 'package:core/core.dart';
import 'package:database/database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'di/providers.dart';

/// Ponto de entrada comum a todos os flavors. Inicializa serviços, abre o banco
/// local e injeta as instâncias prontas na árvore de providers.
Future<void> bootstrap(AppEnv env) async {
  WidgetsFlutterBinding.ensureInitialized();

  AppLogger.configure(level: env.flavor.isProd ? Level.WARNING : Level.ALL);
  final log = AppLogger('bootstrap');

  await runZonedGuarded(
    () async {
      FlutterError.onError = (details) =>
          log.severe('FlutterError', details.exception, details.stack);

      await Supabase.initialize(
        url: env.supabaseUrl,
        publishableKey: env.supabaseAnonKey,
      );

      final dbPath = await resolveDatabasePath();
      final powerSync = await PowerSyncService.open(path: dbPath);
      final connector = SupabaseConnector(powerSyncUrl: env.powersyncUrl);

      runApp(
        ProviderScope(
          overrides: [
            appEnvProvider.overrideWithValue(env),
            powerSyncServiceProvider.overrideWithValue(powerSync),
            supabaseConnectorProvider.overrideWithValue(connector),
          ],
          child: const FinanceApp(),
        ),
      );
    },
    (error, stack) => log.severe('Uncaught zone error', error, stack),
  );
}
