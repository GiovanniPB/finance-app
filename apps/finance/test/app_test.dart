import 'package:core/core.dart';
import 'package:finance/app.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/auth/domain/auth_repository.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/spaces_repository.dart';
import 'package:flutter/material.dart';
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

class FakeSpacesRepository implements SpacesRepository {
  @override
  Stream<List<Space>> watchAll() => Stream.value([
    Space(
      id: 'p1',
      type: SpaceType.personal,
      name: 'Pessoal',
      ownerId: 'user-1',
      privacy: SpacePrivacy.sharedOnly,
      status: SpaceStatus.active,
      settlementCurrency: 'BRL',
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
  ]);

  @override
  Stream<Space?> watchById(String id) => Stream.value(null);
}

void main() {
  Future<void> pumpApp(WidgetTester tester, {AuthUser? user}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: user),
          ),
          spacesRepositoryProvider.overrideWithValue(FakeSpacesRepository()),
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
}
