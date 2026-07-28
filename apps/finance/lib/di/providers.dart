import 'package:core/core.dart';
import 'package:database/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/accounts/data/accounts_repository_impl.dart';
import '../features/accounts/domain/accounts_repository.dart';
import '../features/auth/data/auth_repository_impl.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/budgets/data/budgets_repository_impl.dart';
import '../features/budgets/domain/budgets_repository.dart';
import '../features/categories/data/categories_repository_impl.dart';
import '../features/categories/domain/categories_repository.dart';
import '../features/onboarding/data/onboarding_store.dart';
import '../features/onboarding/domain/onboarding_preferences.dart';
import '../features/open_finance/data/open_finance_repository_impl.dart';
import '../features/open_finance/domain/open_finance_repository.dart';
import '../features/savings/data/savings_repository_impl.dart';
import '../features/savings/domain/savings_repository.dart';
import '../features/spaces/data/spaces_repository_impl.dart';
import '../features/spaces/domain/spaces_repository.dart';
import '../features/transactions/data/transactions_repository_impl.dart';
import '../features/transactions/domain/transactions_repository.dart';

part 'providers.g.dart';

/// Configuração de ambiente. Sobrescrito no `bootstrap` com o valor resolvido.
@Riverpod(keepAlive: true)
AppEnv appEnv(Ref ref) =>
    throw UnimplementedError('appEnvProvider é sobrescrito no bootstrap');

/// Relógio da aplicação, injetável.
///
/// Os repositories já recebem `now` no construtor; isto é o equivalente para a
/// camada de apresentação, onde há cálculo que depende de "hoje" — o ritmo de
/// uma meta contra o prazo, por exemplo. Sem um relógio substituível, um teste
/// desses só passaria no dia em que foi escrito.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;

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

@Riverpod(keepAlive: true)
SpacesRepository spacesRepository(Ref ref) =>
    SpacesRepositoryImpl(db: ref.watch(powerSyncServiceProvider).db);

/// Conexões de Open Finance. Depende do `SupabaseClient` por dois motivos:
/// identificar o dono nas leituras **e** invocar a Edge Function que emite o
/// Connect Token (ADR 0005 — o cliente nunca fala com a Pluggy direto).
@Riverpod(keepAlive: true)
OpenFinanceRepository openFinanceRepository(Ref ref) =>
    OpenFinanceRepositoryImpl(
      db: ref.watch(powerSyncServiceProvider).db,
      supabase: ref.watch(supabaseClientProvider),
    );

@Riverpod(keepAlive: true)
CategoriesRepository categoriesRepository(Ref ref) =>
    CategoriesRepositoryImpl(db: ref.watch(powerSyncServiceProvider).db);

@Riverpod(keepAlive: true)
TransactionsRepository transactionsRepository(Ref ref) =>
    TransactionsRepositoryImpl(
      db: ref.watch(powerSyncServiceProvider).db,
      supabase: ref.watch(supabaseClientProvider),
    );

@Riverpod(keepAlive: true)
BudgetsRepository budgetsRepository(Ref ref) =>
    BudgetsRepositoryImpl(db: ref.watch(powerSyncServiceProvider).db);

@Riverpod(keepAlive: true)
SavingsRepository savingsRepository(Ref ref) => SavingsRepositoryImpl(
  db: ref.watch(powerSyncServiceProvider).db,
  supabase: ref.watch(supabaseClientProvider),
);

@Riverpod(keepAlive: true)
OnboardingPreferences onboardingStore(Ref ref) =>
    OnboardingStore(db: ref.watch(powerSyncServiceProvider).db);
