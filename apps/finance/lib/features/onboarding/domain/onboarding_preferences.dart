import 'package:core/core.dart';

/// Contrato da preferência de primeira execução.
///
/// Existe como interface pelo mesmo motivo dos repositories: a tela depende do
/// contrato, e o teste troca a implementação por um fake sem precisar de banco.
abstract interface class OnboardingPreferences {
  /// Se a apresentação inicial já foi concluída ou pulada.
  Future<bool> hasSeen();

  /// Marca como vista. Idempotente.
  Future<Result<void, Failure>> markSeen();
}
