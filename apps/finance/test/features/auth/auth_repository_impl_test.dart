import 'package:core/core.dart';
import 'package:finance/features/auth/data/auth_repository_impl.dart';
import 'package:finance/features/auth/domain/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

class MockAuthResponse extends Mock implements AuthResponse {}

void main() {
  late MockSupabaseClient supabase;
  late MockGoTrueClient auth;
  late AuthRepositoryImpl repo;

  setUp(() {
    supabase = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => supabase.auth).thenReturn(auth);
    repo = AuthRepositoryImpl(supabase: supabase);
  });

  User buildUser() {
    final user = MockUser();
    when(() => user.id).thenReturn('user-1');
    when(() => user.email).thenReturn('ana@example.com');
    return user;
  }

  group('currentUser', () {
    test('mapeia User do Supabase para AuthUser', () {
      final mockUser = buildUser();
      when(() => auth.currentUser).thenReturn(mockUser);
      final user = repo.currentUser;
      expect(user, isA<AuthUser>());
      expect(user?.id, 'user-1');
      expect(user?.email, 'ana@example.com');
    });

    test('retorna null quando não autenticado', () {
      when(() => auth.currentUser).thenReturn(null);
      expect(repo.currentUser, isNull);
    });
  });

  group('signInWithPassword', () {
    test('retorna Ok com o usuário em caso de sucesso', () async {
      final response = MockAuthResponse();
      final mockUser = buildUser();
      when(() => response.user).thenReturn(mockUser);
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => response);

      final result = await repo.signInWithPassword(
        email: 'ana@example.com',
        password: 'secret',
      );

      expect(result.valueOrNull?.id, 'user-1');
    });

    test('retorna AuthFailure quando o Supabase lança AuthException', () async {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        const AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      );

      final result = await repo.signInWithPassword(
        email: 'ana@example.com',
        password: 'wrong',
      );

      expect(result.failureOrNull, isA<AuthFailure>());
      // A frase do SDK é em inglês e ia crua para a tela; o repository traduz
      // na fronteira. Ver `auth_error_message.dart`.
      expect(result.failureOrNull?.message, 'E-mail ou senha incorretos.');
    });

    test('retorna AuthFailure quando a resposta não tem usuário', () async {
      final response = MockAuthResponse();
      when(() => response.user).thenReturn(null);
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => response);

      final result = await repo.signInWithPassword(
        email: 'x@y.com',
        password: 'z',
      );

      expect(result.failureOrNull, isA<AuthFailure>());
    });
  });

  group('signUp', () {
    test('retorna Ok com o usuário em caso de sucesso', () async {
      final response = MockAuthResponse();
      final mockUser = buildUser();
      when(() => response.user).thenReturn(mockUser);
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => response);

      final result = await repo.signUp(
        email: 'ana@example.com',
        password: 'secret',
      );

      expect(result.valueOrNull?.email, 'ana@example.com');
    });
  });

  group('signOut', () {
    test('retorna Ok em caso de sucesso', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});
      final result = await repo.signOut();
      expect(result.isOk, isTrue);
    });

    test('retorna AuthFailure quando o Supabase lança', () async {
      when(() => auth.signOut()).thenThrow(const AuthException('falhou'));
      final result = await repo.signOut();
      expect(result.failureOrNull, isA<AuthFailure>());
    });
  });
}
