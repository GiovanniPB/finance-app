import 'package:core/core.dart';

/// Usuário autenticado, desacoplado do SDK do Supabase.
class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

/// Contrato de autenticação. A apresentação depende desta interface.
abstract interface class AuthRepository {
  /// Usuário atual, ou `null` se não autenticado.
  AuthUser? get currentUser;

  /// Emite a cada mudança de sessão (login, logout, refresh).
  Stream<AuthUser?> authStateChanges();

  Future<Result<AuthUser, Failure>> signInWithPassword({
    required String email,
    required String password,
  });

  Future<Result<AuthUser, Failure>> signUp({
    required String email,
    required String password,
  });

  Future<Result<void, Failure>> signOut();
}
