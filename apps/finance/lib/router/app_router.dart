import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/onboarding/presentation/onboarding_providers.dart';
import '../features/shell/presentation/app_shell.dart';

part 'app_router.g.dart';

/// Rotas nomeadas da aplicação.
abstract final class Routes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const onboarding = '/apresentacao';
}

/// Router da aplicação com guard de autenticação e de primeira execução.
///
/// Reconstrói quando o estado de auth ou de apresentação muda (via
/// `ref.watch`), reavaliando o redirect. A ordem dos portões importa:
/// **autenticar primeiro, apresentar depois**. A apresentação termina abrindo o
/// registro rápido, que precisa de espaço ativo — e espaço só existe depois do
/// login.
@riverpod
GoRouter goRouter(Ref ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final seenOnboarding = ref.watch(onboardingSeenProvider);

  return GoRouter(
    initialLocation: Routes.home,
    redirect: (context, state) {
      final location = state.matchedLocation;

      if (!isAuthenticated) {
        return location == Routes.signIn ? null : Routes.signIn;
      }
      if (!seenOnboarding) {
        return location == Routes.onboarding ? null : Routes.onboarding;
      }
      // Autenticado e já apresentado: sign-in e apresentação não têm mais razão
      // de existir na pilha.
      return location == Routes.signIn || location == Routes.onboarding
          ? Routes.home
          : null;
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
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
    ],
  );
}
