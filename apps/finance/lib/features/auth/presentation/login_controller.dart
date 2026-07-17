import 'dart:async';

import 'package:core/core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../domain/auth_repository.dart';

part 'login_controller.g.dart';

/// Estado do formulário de login: `data` = ocioso/sucesso, `loading` = em
/// andamento, `error` = falha (o objeto de erro é a [Failure]).
///
/// Navegação não é responsabilidade daqui: ao autenticar, o guard do router
/// reage à mudança de `authStateProvider` e redireciona.
@riverpod
class LoginController extends _$LoginController {
  @override
  FutureOr<void> build() {}

  Future<void> signIn({required String email, required String password}) =>
      _submit(
        () => ref
            .read(authRepositoryProvider)
            .signInWithPassword(email: email, password: password),
      );

  Future<void> signUp({required String email, required String password}) =>
      _submit(
        () => ref
            .read(authRepositoryProvider)
            .signUp(email: email, password: password),
      );

  Future<void> _submit(
    Future<Result<AuthUser, Failure>> Function() action,
  ) async {
    state = const AsyncValue.loading();
    final result = await action();
    state = switch (result) {
      Ok() => const AsyncValue.data(null),
      Err(:final failure) => AsyncValue.error(failure, StackTrace.current),
    };
  }
}
