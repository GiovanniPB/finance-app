import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';

part 'onboarding_providers.g.dart';

/// Se a apresentação já havia sido vista **no momento do boot**.
///
/// Lido uma vez no `bootstrap` e injetado por `overrideWithValue`, para o guard
/// de rota poder decidir de forma síncrona: um `AsyncValue` aqui obrigaria o
/// router a ter um estado de carregamento no primeiro frame, e o primeiro frame
/// é justamente o que a apresentação existe para aproveitar.
@Riverpod(keepAlive: true)
bool onboardingSeenAtBoot(Ref ref) => throw UnimplementedError(
  'onboardingSeenAtBootProvider é sobrescrito no bootstrap',
);

/// Estado de "já viu a apresentação", com a gravação embutida.
@Riverpod(keepAlive: true)
class OnboardingSeen extends _$OnboardingSeen {
  @override
  bool build() => ref.watch(onboardingSeenAtBootProvider);

  /// Conclui (ou pula) a apresentação.
  ///
  /// O estado vira `true` **mesmo se a gravação falhar**: prender alguém na
  /// apresentação por causa de um erro de disco seria pior que repeti-la no
  /// próximo boot. A falha é registrada pelo store.
  Future<void> complete() async {
    await ref.read(onboardingStoreProvider).markSeen();
    state = true;
  }
}
