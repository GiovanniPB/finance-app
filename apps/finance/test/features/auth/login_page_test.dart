import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/auth/domain/auth_repository.dart';
import 'package:finance/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  Result<AuthUser, Failure> result = const Ok(AuthUser(id: 'user-1'));

  @override
  Future<Result<AuthUser, Failure>> signInWithPassword({
    required String email,
    required String password,
  }) async => result;

  @override
  Future<Result<AuthUser, Failure>> signUp({
    required String email,
    required String password,
  }) async => result;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<Result<void, Failure>> signOut() async => const Ok(null);
}

void main() {
  Future<void> pump(WidgetTester tester, FakeAuthRepository auth) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(auth)],
          child: const MaterialApp(home: LoginPage()),
        ),
      );

  testWidgets('exibe a mensagem de falha quando o login falha', (tester) async {
    final auth = FakeAuthRepository()
      ..result = const Err(AuthFailure('Credenciais inválidas'));
    await pump(tester, auth);

    await tester.enterText(find.byKey(const Key('login_email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('login_password')), '123456');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_error')), findsOneWidget);
    expect(find.text('Credenciais inválidas'), findsOneWidget);
  });

  testWidgets('valida e-mail inválido sem chamar o repositório', (
    tester,
  ) async {
    await pump(tester, FakeAuthRepository());

    await tester.enterText(find.byKey(const Key('login_email')), 'invalido');
    await tester.enterText(find.byKey(const Key('login_password')), '123456');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Informe um e-mail válido'), findsOneWidget);
  });

  testWidgets('alterna entre entrar e criar conta', (tester) async {
    await pump(tester, FakeAuthRepository());

    expect(find.text('Entrar'), findsOneWidget);
    await tester.tap(find.text('Não tenho conta — criar'));
    await tester.pumpAndSettle();
    expect(find.text('Criar conta'), findsOneWidget);
  });
}
