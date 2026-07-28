import 'package:core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../domain/auth_repository.dart';
import 'auth_error_message.dart';

/// Implementação sobre o Supabase Auth.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required this.supabase, AppLogger? logger})
    : _log = logger ?? AppLogger('AuthRepository');

  final SupabaseClient supabase;
  final AppLogger _log;

  @override
  AuthUser? get currentUser => _toUser(supabase.auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() => supabase.auth.onAuthStateChange.map(
    (state) => _toUser(state.session?.user),
  );

  @override
  Future<Result<AuthUser, Failure>> signInWithPassword({
    required String email,
    required String password,
  }) => _guardUser(
    () => supabase.auth.signInWithPassword(email: email, password: password),
  );

  @override
  Future<Result<AuthUser, Failure>> signUp({
    required String email,
    required String password,
  }) =>
      _guardUser(() => supabase.auth.signUp(email: email, password: password));

  @override
  Future<Result<void, Failure>> signOut() async {
    try {
      await supabase.auth.signOut();
      return const Ok(null);
    } on AuthException catch (e, st) {
      _log.warning('Falha no signOut', e, st);
      return Err(AuthFailure(authErrorMessage(e), cause: e));
    }
  }

  Future<Result<AuthUser, Failure>> _guardUser(
    Future<AuthResponse> Function() action,
  ) async {
    try {
      final response = await action();
      final user = _toUser(response.user);
      if (user == null) {
        return const Err(AuthFailure('Resposta de autenticação sem usuário.'));
      }
      return Ok(user);
    } on AuthException catch (e, st) {
      _log.warning('Falha de autenticação', e, st);
      return Err(AuthFailure(authErrorMessage(e), cause: e));
    }
  }

  AuthUser? _toUser(User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);
}
