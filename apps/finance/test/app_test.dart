import 'package:core/core.dart';
import 'package:finance/app.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/auth/domain/auth_repository.dart';
import 'package:finance/features/onboarding/domain/onboarding_preferences.dart';
import 'package:finance/features/onboarding/presentation/onboarding_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/app_harness.dart' show FakeSpacesRepository, personalSpace;

/// Fake sem dependência de Supabase para exercitar o shell (tema + router).
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.user});

  final AuthUser? user;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(user);

  @override
  Future<Result<AuthUser, Failure>> signInWithPassword({
    required String email,
    required String password,
  }) async => const Err(AuthFailure('não usado no teste'));

  @override
  Future<Result<AuthUser, Failure>> signUp({
    required String email,
    required String password,
  }) async => const Err(AuthFailure('não usado no teste'));

  @override
  Future<Result<void, Failure>> signOut() async => const Ok(null);
}

/// Preferência de primeira execução que não toca em banco.
class FakePreferences implements OnboardingPreferences {
  FakePreferences({this.seen = true});

  final bool seen;
  int marked = 0;

  @override
  Future<bool> hasSeen() async => seen || marked > 0;

  @override
  Future<Result<void, Failure>> markSeen() async {
    marked++;
    return const Ok(null);
  }
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    AuthUser? user,
    bool seenOnboarding = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: user),
          ),
          spacesRepositoryProvider.overrideWithValue(
            FakeSpacesRepository([personalSpace()]),
          ),
          onboardingStoreProvider.overrideWithValue(
            FakePreferences(seen: seenOnboarding),
          ),
          onboardingSeenAtBootProvider.overrideWithValue(seenOnboarding),
        ],
        child: const FinanceApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sem sessão, o guard redireciona para o login', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
    expect(find.text('Início'), findsNothing);
  });

  testWidgets('autenticado, exibe a home com o espaço ativo', (tester) async {
    await pumpApp(tester, user: const AuthUser(id: 'user-1'));
    expect(find.text('Início'), findsOneWidget);
    expect(find.byKey(const Key('active_space_name')), findsOneWidget);
    expect(find.text('Pessoal'), findsOneWidget);
  });

  testWidgets('autenticado na primeira vez, cai na apresentação', (
    tester,
  ) async {
    await pumpApp(
      tester,
      user: const AuthUser(id: 'user-1'),
      seenOnboarding: false,
    );

    expect(find.textContaining('Pilar 1'), findsOneWidget);
    expect(find.text('Início'), findsNothing);
  });

  testWidgets('sem sessão, a apresentação não vem antes do login', (
    tester,
  ) async {
    await pumpApp(tester, seenOnboarding: false);

    // A ordem dos portões: autenticar primeiro. A apresentação termina no
    // registro rápido, que precisa de espaço ativo.
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
    expect(find.textContaining('Pilar 1'), findsNothing);
  });

  testWidgets('pular a apresentação leva à home', (tester) async {
    await pumpApp(
      tester,
      user: const AuthUser(id: 'user-1'),
      seenOnboarding: false,
    );

    await tester.tap(find.byKey(const Key('onboarding_skip')));
    await tester.pumpAndSettle();

    expect(find.text('Início'), findsOneWidget);
    expect(find.textContaining('Pilar 1'), findsNothing);
  });
}
