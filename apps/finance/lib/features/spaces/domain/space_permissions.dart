import 'space.dart';
import 'space_member.dart';

/// O que **quem está olhando** pode fazer neste espaço (matriz do PRD §7).
///
/// ─────────────────────────────────────────────────────────────────────────
/// POR QUE ISTO EXISTE EM VEZ DE UM `if` NA TELA
///
/// Num app offline-first a escrita é local e sobe depois. O
/// `SupabaseConnector` descarta o batch quando o Postgres recusa — senão a fila
/// travaria para sempre —, e o efeito colateral é que **uma escrita barrada
/// pela RLS não vira erro na tela**: ela aparece aplicada e some no checkpoint
/// seguinte. Foi exatamente assim que o espaço novo "aparecia e sumia".
///
/// Então a regra precisa existir dos dois lados, e das duas o cliente é o que
/// fala com a pessoa. Este objeto é a versão em Dart do que a migration
/// `20260728210321` grava em policy e trigger — e a razão de as duas listas
/// abaixo terem de andar juntas quando uma mudar.
///
/// ─────────────────────────────────────────────────────────────────────────
/// AS INVARIANTES, E DE ONDE CADA UMA VEM
///
/// • **Quem criou é sempre admin.** Não se rebaixa nem se remove. Sem isso um
///   admin toma o espaço de quem o criou. (Trigger `space_members_guard`.)
/// • **O dono não sai; arquiva.** Um espaço cujo `owner_id` aponta para quem
///   não está mais nele é um espaço sem responsável.
/// • **Espaço arquivado é histórico.** Dá para ler e para sair, não para
///   convidar, renomear ou mexer em quem está nele.
/// • **Remover-se não é remover.** Sair é outra ação, com outra frase e outra
///   consequência para quem fica.
class SpacePermissions {
  const SpacePermissions({
    required this.space,
    required this.myUserId,
    required this.myRole,
  });

  final Space space;

  /// Quem está usando o app. Nulo sem sessão.
  final String? myUserId;

  /// O papel de quem está usando o app **neste** espaço.
  ///
  /// Nulo enquanto a membership não sincronizou, e nulo é tratado como "não
  /// pode": prometer uma permissão que o servidor vai recusar é pior do que
  /// esconder o controle até saber.
  final SpaceRole? myRole;

  bool get _isAdmin => myRole?.canManageMembers ?? false;

  /// Espaço arquivado aceita leitura e saída, não gestão.
  bool get _isLive => !space.isArchived;

  /// Sou a pessoa que criou o espaço.
  bool get isOwner => myUserId != null && myUserId == space.ownerId;

  /// O Espaço Pessoal tem um membro só e não recebe convite (PRD §4.3).
  bool get isShared => !space.isPersonal;

  bool get canInvite => isShared && _isAdmin && _isLive;

  /// Renomear vale também para o Pessoal: é um espaço como os outros, e a RLS
  /// já aceita o dono editando o próprio.
  bool get canRename => (_isAdmin || isOwner) && _isLive;

  bool get canArchive => isShared && (_isAdmin || isOwner) && _isLive;

  bool get canManageMembers => isShared && _isAdmin && _isLive;

  /// Sair continua valendo em espaço arquivado — é justamente onde faz sentido
  /// limpar. Quem criou não sai: arquiva.
  bool get canLeave => isShared && !isOwner && myRole != null;

  /// Por que o botão de sair não está aí, quando não está.
  ///
  /// Devolve nulo quando dá para sair. Existe porque a alternativa a explicar é
  /// um espaço em que a pessoa não acha a saída e conclui que não há.
  String? get whyCannotLeave {
    if (!isShared) return null;
    if (isOwner) {
      return 'Você criou este espaço. Para encerrá-lo, arquive — assim o '
          'histórico fica de pé para quem participou.';
    }
    return null;
  }

  bool isOwnerRow(SpaceMember member) => member.userId == space.ownerId;

  bool isMe(SpaceMember member) =>
      myUserId != null && member.userId == myUserId;

  /// Trocar o papel de alguém. A linha de quem criou fica de fora.
  ///
  /// A **própria** linha entra: um admin que não é o dono pode se rebaixar, e
  /// isso não deixa o espaço órfão, porque o dono é admin por construção.
  bool canChangeRoleOf(SpaceMember member) =>
      canManageMembers && !isOwnerRow(member);

  /// Remover alguém. Nem o dono, nem eu mesmo (para isso existe sair).
  bool canRemove(SpaceMember member) =>
      canManageMembers && !isOwnerRow(member) && !isMe(member);
}
