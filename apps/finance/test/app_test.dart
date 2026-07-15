import 'package:core/core.dart';
import 'package:finance/app.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/auth/domain/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  Future<void> pumpApp(WidgetTester tester, {AuthUser? user}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: user),
          ),
        ],
        child: const FinanceApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sem sessão, o guard redireciona para o sign-in', (tester) async {
    await pumpApp(tester);
    expect(find.text('Sign in (placeholder)'), findsOneWidget);
    expect(find.text('Home (placeholder)'), findsNothing);
  });

  testWidgets('autenticado, exibe a home', (tester) async {
    await pumpApp(tester, user: const AuthUser(id: 'user-1'));
    expect(find.text('Home (placeholder)'), findsOneWidget);
    expect(find.text('Sign in (placeholder)'), findsNothing);
  });
}
