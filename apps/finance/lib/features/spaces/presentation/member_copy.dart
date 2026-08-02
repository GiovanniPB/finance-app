import 'package:core/core.dart';

import '../domain/space_member.dart';
import '../domain/space_permissions.dart';

/// Como a linha de membro se apresenta: um rótulo e, às vezes, um qualificador.
///
/// O qualificador vem separado do rótulo porque a lista o pinta em cor apagada
/// — "Ana Prado" e "· quem criou o espaço" têm pesos diferentes na leitura.
/// Juntar os dois numa string só obrigaria a UI a fatiar de novo o que aqui já
/// está separado.
typedef MemberIdentity = ({String label, String? qualifier});

extension MemberIdentityText on MemberIdentity {
  /// Rótulo e qualificador numa frase só.
  ///
  /// Para onde não há duas cores para separar — o título da folha de ações, e
  /// qualquer leitor de tela.
  String get text => qualifier == null ? label : '$label · $qualifier';
}

/// As frases da lista de membros.
///
/// ─────────────────────────────────────────────────────────────────────────
/// COM NOME, O NOME LIDERA — E A DATA DE ENTRADA SAI DE CENA
///
/// A data existia como muleta de desempate: com três "Editor" idênticos,
/// "remover" virava sorteio, e ela é única na prática. O nome faz esse trabalho
/// melhor e responde à pergunta que a pessoa realmente tinha. Quando há nome, a
/// data não aparece; ninguém abre a lista de membros para saber quando alguém
/// entrou.
///
/// ─────────────────────────────────────────────────────────────────────────
/// O MEU NOME E O DOS OUTROS VÊM DE LUGARES DIFERENTES, DE PROPÓSITO
///
/// [identity] recebe `myDisplayName` em separado, lido de `profiles`, e ele
/// vence para a minha linha. O `display_name` de `space_members` é cópia
/// mantida por trigger no Postgres: entre eu salvar o nome no Perfil e o
/// round-trip completar, a minha própria membership ainda carrega o valor
/// velho. Sem esta precedência, eu trocaria o nome e veria a linha antiga —
/// offline, para sempre.
///
/// Para as outras linhas não há escolha: o perfil de outra pessoa não chega ao
/// aparelho (bucket `user_owned` entrega só o meu), e é justamente por isso que
/// a coluna copiada existe.
abstract final class MemberCopy {
  /// Como a linha se apresenta.
  ///
  /// Sem nome nenhum, devolve exatamente as frases que a tela usava antes de a
  /// coluna existir — é o estado de toda linha até a pessoa abrir o Perfil.
  static MemberIdentity identity({
    required SpaceMember member,
    required SpacePermissions permissions,
    required DateTime today,
    String? myDisplayName,
  }) {
    final isMe = permissions.isMe(member);
    final isOwner = permissions.isOwnerRow(member);
    final name = isMe
        ? myDisplayName ?? member.displayName
        : member.displayName;

    if (name != null) {
      return (
        label: name,
        qualifier: switch ((isMe, isOwner)) {
          (true, true) => 'você, que criou o espaço',
          (true, false) => 'você',
          (false, true) => 'quem criou o espaço',
          (false, false) => null,
        },
      );
    }

    if (isMe && isOwner) {
      return (label: 'Você, que criou o espaço', qualifier: null);
    }
    if (isMe) return (label: 'Você', qualifier: null);
    if (isOwner) return (label: 'Quem criou o espaço', qualifier: null);

    return (
      label:
          'No espaço desde '
          '${formatDayLabel(member.joinedAt, today: today).toLowerCase()}',
      qualifier: null,
    );
  }

  /// O nome curto, para caber numa linha com outra pessoa do lado.
  ///
  /// ─────────────────────────────────────────────────────────────────────────
  /// POR QUE NÃO REUSAR [identity] AQUI
  ///
  /// O fallback de [identity] é "No espaço desde 28 de julho" — bom numa lista
  /// de membros, onde a data desempata três "Editor" idênticos, e ilegível numa
  /// transferência: *"No espaço desde 28 de julho → Você"*. A linha de acerto
  /// tem duas pessoas e um valor, e precisa de rótulos curtos nas duas pontas.
  ///
  /// "Membro sem nome" é levemente acusatório com quem nunca abriu o Perfil, e
  /// foi escolhido assim mesmo (2026-08-01): repetido duas vezes ele não
  /// desempata, mas duas pessoas sem nome num grupo pequeno é raro, e a saída é
  /// a pessoa definir o nome — que é o que o rótulo pede sem dizer.
  ///
  /// [userId] pode não ter membership: quem saiu do espaço depois de a despesa
  /// ser dividida continua no saldo, porque a dívida não sai com a pessoa.
  ///
  /// Não recebe `myDisplayName`, ao contrário de [identity]: a minha ponta é
  /// sempre "Você". Numa linha com duas pessoas o pronome é o que se acha mais
  /// rápido, e o meu nome ao lado do nome de outro obrigaria a ler os dois.
  static MemberIdentity shortIdentity({
    required String userId,
    required List<SpaceMember> members,
    required SpacePermissions permissions,
  }) {
    if (permissions.myUserId == userId) {
      return (label: 'Você', qualifier: null);
    }

    final member = members.where((m) => m.userId == userId).firstOrNull;
    if (member == null) {
      return (label: 'Membro sem nome', qualifier: 'saiu do espaço');
    }

    return (
      label: member.displayName ?? 'Membro sem nome',
      qualifier: member.isActive ? null : 'saiu do espaço',
    );
  }

  /// A segunda linha: o papel e o que ele permite, juntos.
  ///
  /// "Editor" sozinho não diz nada a quem nunca leu a matriz de permissões; a
  /// frase ao lado é o que transforma o rótulo em informação.
  static String role(SpaceRole role) => '${role.label} · ${role.description}';
}
