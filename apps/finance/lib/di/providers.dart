import 'package:core/core.dart';
import 'package:database/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/accounts/data/accounts_repository_impl.dart';
import '../features/accounts/domain/accounts_repository.dart';
import '../features/auth/data/auth_repository_impl.dart';
import '../features/auth/domain/auth_repository.dart';

part 'providers.g.dart';

/// Configuração de ambiente. Sobrescrito no `bootstrap` com o valor resolvido.
@Riverpod(keepAlive: true)
AppEnv appEnv(Ref ref) =>
    throw UnimplementedError('appEnvProvider é sobrescrito no bootstrap');

/// Cliente Supabase (inicializado no `bootstrap` via Supabase.initialize).
@Riverpod(keepAlive: true)
SupabaseClient supabaseClient(Ref ref) => Supabase.instance.client;

/// Serviço PowerSync. Sobrescrito no `bootstrap` com a instância já aberta.
@Riverpod(keepAlive: true)
PowerSyncService powerSyncService(Ref ref) => throw UnimplementedError(
  'powerSyncServiceProvider deve ser sobrescrito no bootstrap',
);

/// Conector PowerSync↔Supabase. Sobrescrito no `bootstrap`.
@Riverpod(keepAlive: true)
SupabaseConnector supabaseConnector(Ref ref) => throw UnimplementedError(
  'supabaseConnectorProvider deve ser sobrescrito no bootstrap',
);

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) =>
    AuthRepositoryImpl(supabase: ref.watch(supabaseClientProvider));

@Riverpod(keepAlive: true)
AccountsRepository accountsRepository(Ref ref) => AccountsRepositoryImpl(
  db: ref.watch(powerSyncServiceProvider).db,
  supabase: ref.watch(supabaseClientProvider),
);
