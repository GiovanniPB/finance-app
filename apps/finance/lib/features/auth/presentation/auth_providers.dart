import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../domain/auth_repository.dart';

part 'auth_providers.g.dart';

/// Estado reativo da sessão do usuário (null = não autenticado).
@riverpod
Stream<AuthUser?> authState(Ref ref) =>
    ref.watch(authRepositoryProvider).authStateChanges();

/// `true` quando há um usuário autenticado.
@riverpod
bool isAuthenticated(Ref ref) {
  final auth = ref.watch(authStateProvider);
  return auth.asData?.value != null;
}
