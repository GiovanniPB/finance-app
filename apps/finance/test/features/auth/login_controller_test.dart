import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/auth/domain/auth_repository.dart';
import 'package:finance/features/auth/presentation/login_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  Result<AuthUser, Failure> signInResult = const Ok(AuthUser(id: 'user-1'));

  @override
  Future<Result<AuthUser, Failure>> signInWithPassword({
    required String email,
    required String password,
  }) async => signInResult;

  @override
  Future<Result<AuthUser, Failure>> signUp({
    required String email,
    required String password,
  }) async => signInResult;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<Result<void, Failure>> signOut() async => const Ok(null);
}

void main() {
  late FakeAuthRepository auth;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => auth = FakeAuthRepository());

  test('signIn com sucesso deixa o estado em data', () async {
    final container = makeContainer();
    await container
        .read(loginControllerProvider.notifier)
        .signIn(email: 'a@b.com', password: '123456');

    expect(container.read(loginControllerProvider).hasError, isFalse);
    expect(container.read(loginControllerProvider).isLoading, isFalse);
  });

  test('signIn com falha expõe a Failure no estado de erro', () async {
    auth.signInResult = const Err(AuthFailure('Credenciais inválidas'));
    final container = makeContainer();

    await container
        .read(loginControllerProvider.notifier)
        .signIn(email: 'a@b.com', password: 'wrong1');

    final state = container.read(loginControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<AuthFailure>());
  });

  test('signUp delega ao repositório e reflete o resultado', () async {
    auth.signInResult = const Err(AuthFailure('E-mail já usado'));
    final container = makeContainer();

    await container
        .read(loginControllerProvider.notifier)
        .signUp(email: 'a@b.com', password: '123456');

    expect(container.read(loginControllerProvider).hasError, isTrue);
  });
}
