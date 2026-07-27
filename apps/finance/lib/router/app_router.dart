import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/shell/presentation/app_shell.dart';

part 'app_router.g.dart';

/// Rotas nomeadas da aplicação.
abstract final class Routes {
  static const home = '/';
  static const signIn = '/sign-in';
}

/// Router da aplicação com guard de autenticação.
///
/// Reconstrói quando o estado de auth muda (via `ref.watch`), reavaliando o
/// redirect: usuários não autenticados vão para [Routes.signIn]; autenticados
/// que caírem no sign-in voltam para [Routes.home].
@riverpod
GoRouter goRouter(Ref ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);

  return GoRouter(
    initialLocation: Routes.home,
    redirect: (context, state) {
      final goingToSignIn = state.matchedLocation == Routes.signIn;
      if (!isAuthenticated && !goingToSignIn) return Routes.signIn;
      if (isAuthenticated && goingToSignIn) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const AppShell(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const LoginPage(),
      ),
    ],
  );
}
