import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../domain/space.dart';

part 'spaces_providers.g.dart';

/// Lista reativa de espaços do usuário (offline-first).
@riverpod
Stream<List<Space>> spaces(Ref ref) =>
    ref.watch(spacesRepositoryProvider).watchAll();

/// Id do espaço ativo selecionado pelo usuário. `null` = usar o padrão
/// (Espaço Pessoal). Cross-cutting: repositórios com escopo de espaço filtram
/// suas queries por este id (ver ADR 0004).
@riverpod
class ActiveSpaceId extends _$ActiveSpaceId {
  @override
  String? build() => null;

  /// Seleciona um espaço (ou `null` para voltar ao padrão pessoal).
  // ignore: use_setters_to_change_properties
  void select(String? spaceId) => state = spaceId;
}

/// Espaço ativo resolvido: o selecionado, ou o Espaço Pessoal como padrão.
///
/// `null` enquanto os espaços ainda não sincronizaram (primeiro boot offline).
@riverpod
Space? activeSpace(Ref ref) {
  final spaces = ref.watch(spacesProvider).asData?.value ?? const <Space>[];
  if (spaces.isEmpty) return null;

  final activeId = ref.watch(activeSpaceIdProvider);
  if (activeId != null) {
    for (final space in spaces) {
      if (space.id == activeId) return space;
    }
  }

  // Padrão: Espaço Pessoal (sempre existe; criado no signup).
  return spaces.firstWhere(
    (space) => space.isPersonal,
    orElse: () => spaces.first,
  );
}
