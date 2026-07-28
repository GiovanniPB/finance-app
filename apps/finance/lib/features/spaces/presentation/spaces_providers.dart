import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../domain/space.dart';
import '../domain/space_member.dart';

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

/// Membros ativos de um espaço.
@riverpod
Stream<List<SpaceMember>> spaceMembers(Ref ref, String spaceId) =>
    ref.watch(spacesRepositoryProvider).watchMembers(spaceId);

/// O papel de **quem está usando o app** neste espaço.
///
/// Nulo enquanto a membership não sincronizou, e a UI trata nulo como "não
/// pode": prometer uma permissão que o servidor vai recusar é pior do que
/// esconder o controle até saber.
@riverpod
SpaceRole? myRoleInSpace(Ref ref, String spaceId) {
  final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return null;

  final members = ref.watch(spaceMembersProvider(spaceId)).asData?.value;
  if (members == null) return null;

  for (final member in members) {
    if (member.userId == userId) return member.role;
  }
  return null;
}

/// Espaços compartilhados (tudo que não é o Pessoal).
///
/// Separado porque as duas listas respondem a coisas diferentes na tela: o
/// Pessoal é o padrão que sempre existe, e os compartilhados são os que a
/// pessoa entrou ou criou — e é a ausência **deles** que justifica o convite a
/// criar o primeiro.
@riverpod
List<Space> sharedSpaces(Ref ref) {
  final spaces = ref.watch(spacesProvider).asData?.value ?? const <Space>[];
  return List.unmodifiable(spaces.where((s) => !s.isPersonal));
}
