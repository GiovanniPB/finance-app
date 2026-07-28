import 'package:core/core.dart';

import '../domain/space_member.dart';
import '../domain/space_permissions.dart';

/// As frases da lista de membros.
///
/// ─────────────────────────────────────────────────────────────────────────
/// AINDA NÃO HÁ NOME DE PESSOA, E ISSO MUDA O QUE A LINHA PRECISA DIZER
///
/// `profiles.display_name` só sincroniza para o próprio dono: as sync rules
/// entregam o perfil no bucket `user_owned`, e o de outro membro não chega ao
/// aparelho. Trazer nomes exige um bucket novo e **republicar as sync rules no
/// dashboard** — passo manual que é a causa conhecida de "tela vazia sem erro"
/// aqui. Fica como próximo passo, não como pré-requisito desta tela.
///
/// Enquanto isso, a linha precisa ser distinguível de outra do mesmo papel: com
/// três "Editor" idênticos, "remover" vira sorteio. Por isso a identidade cai
/// para a data de entrada, que é única na prática e verdadeira sempre — e
/// **não** para o `user_id`, que é um uuid e não identifica ninguém para quem
/// está olhando.
abstract final class MemberCopy {
  /// Como a linha se apresenta.
  static String identity({
    required SpaceMember member,
    required SpacePermissions permissions,
    required DateTime today,
  }) {
    final isMe = permissions.isMe(member);
    final isOwner = permissions.isOwnerRow(member);

    if (isMe && isOwner) return 'Você, que criou o espaço';
    if (isMe) return 'Você';
    if (isOwner) return 'Quem criou o espaço';

    return 'No espaço desde '
        '${formatDayLabel(member.joinedAt, today: today).toLowerCase()}';
  }

  /// A segunda linha: o papel e o que ele permite, juntos.
  ///
  /// "Editor" sozinho não diz nada a quem nunca leu a matriz de permissões; a
  /// frase ao lado é o que transforma o rótulo em informação.
  static String role(SpaceRole role) => '${role.label} · ${role.description}';
}
