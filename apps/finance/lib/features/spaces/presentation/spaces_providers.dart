import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../transactions/domain/month_summary.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/space.dart';
import '../domain/space_member.dart';
import '../domain/space_permissions.dart';

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

/// Um espaço específico, reativo.
///
/// Emite `null` quando o espaço deixa de existir no banco local — que é o que
/// acontece com quem sai ou é removido, porque as sync rules deixam de entregar
/// o bucket. A tela de detalhe depende disso para se fechar sozinha.
@riverpod
Stream<Space?> spaceById(Ref ref, String spaceId) =>
    ref.watch(spacesRepositoryProvider).watchById(spaceId);

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
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final members = ref.watch(spaceMembersProvider(spaceId)).asData?.value;
  if (members == null) return null;

  for (final member in members) {
    if (member.userId == userId) return member.role;
  }
  return null;
}

/// O que dá para fazer neste espaço, do ponto de vista de quem está olhando.
///
/// Nulo enquanto o espaço não está no banco local. A regra em si é pura e mora
/// no domínio ([SpacePermissions]); este provider só junta as três entradas.
@riverpod
SpacePermissions? spacePermissions(Ref ref, String spaceId) {
  final space = ref.watch(spaceByIdProvider(spaceId)).asData?.value;
  if (space == null) return null;

  return SpacePermissions(
    space: space,
    myUserId: ref.watch(currentUserIdProvider),
    myRole: ref.watch(myRoleInSpaceProvider(spaceId)),
  );
}

/// Movimentação do mês corrente **daquele** espaço.
///
/// Diferente de `monthSummaryProvider`, que responde sobre o espaço ativo e
/// segue o mês em foco: aqui a pergunta é "como anda este espaço", feita de
/// dentro da tela dele, e ela não deveria mudar de resposta porque a home ficou
/// olhando abril.
@riverpod
MonthSummary spaceMonthSummary(Ref ref, String spaceId) {
  final now = ref.watch(clockProvider)();
  final from = DateTime(now.year, now.month);
  final to = DateTime(now.year, now.month + 1);

  final transactions = ref
      .watch(
        spaceMonthTransactionsProvider((
          spaceId: spaceId,
          from: from,
          to: to,
        )),
      )
      .asData
      ?.value;

  return transactions == null
      ? MonthSummary.empty
      : MonthSummary.from(transactions);
}

/// Transações de um espaço numa janela. Separado de [spaceMonthSummary] para o
/// stream não ser recriado a cada rebuild do resumo.
@riverpod
Stream<List<Transaction>> spaceMonthTransactions(
  Ref ref,
  ({String spaceId, DateTime from, DateTime to}) window,
) => ref
    .watch(transactionsRepositoryProvider)
    .watchBySpace(window.spaceId, from: window.from, to: window.to);

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
