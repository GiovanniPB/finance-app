import 'package:core/core.dart';

import 'space.dart';
import 'space_member.dart';

/// Acesso aos Espaços do usuário. As leituras são reativas (PowerSync `watch`):
/// o SQLite local já contém apenas os espaços dos quais o usuário é membro
/// (garantido pelas sync rules + RLS — ver ADR 0004).
///
/// ─────────────────────────────────────────────────────────────────────────
/// CRIAR É LOCAL, ENTRAR É REMOTO — E A ASSIMETRIA É DE PROPÓSITO
///
/// [createShared] escreve duas linhas no SQLite local e deixa o PowerSync
/// subi-las: a RLS aceita o dono criando o próprio espaço e a própria
/// membership, então criar um grupo funciona offline como qualquer lançamento.
///
/// [joinByCode] **não pode** ser local. Quem entra ainda não é membro, então
/// não enxerga o espaço nem o convite, e a policy de `space_members` exige ser
/// dono ou admin para inserir. A travessia dessa fronteira é uma RPC
/// `security definer` no Postgres (migration `20260728200052`), e por isso é a
/// única operação daqui que **exige rede**.
abstract interface class SpacesRepository {
  /// Todos os espaços visíveis ao usuário, ordenados por criação.
  Stream<List<Space>> watchAll();

  /// Um espaço específico (ou `null` se não estiver no banco local).
  Stream<Space?> watchById(String id);

  /// Membros **ativos** de um espaço.
  ///
  /// Quem saiu (`left`) fica de fora: a linha continua no banco para o
  /// histórico não ficar órfão, mas uma lista de membros que mostra ex-membros
  /// responde a outra pergunta.
  Stream<List<SpaceMember>> watchMembers(String spaceId);

  /// Cria um espaço compartilhado e põe quem criou como `admin`.
  ///
  /// [type] recusa `personal`: o Espaço Pessoal nasce no signup, é um por
  /// usuário e não removível (PRD §4.3). Um segundo criado aqui passaria pela
  /// RLS e quebraria essa invariante em silêncio.
  Future<Result<Space, Failure>> createShared({
    required SpaceType type,
    required String name,
  });

  /// O código de convite vigente do espaço, criando um se não houver.
  ///
  /// Idempotente: chamar de novo devolve o mesmo código enquanto ele valer.
  /// Só admin — quem não for recebe [Failure].
  Future<Result<String, Failure>> inviteCode(String spaceId);

  /// Entra num espaço com o código, e devolve o id dele.
  ///
  /// Exige rede (ver o cabeçalho). Já ser membro **não** é erro: devolve o
  /// espaço, porque tocar no convite duas vezes é acidente comum.
  Future<Result<String, Failure>> joinByCode(String code);

  // -------------------------------------------------------------------------
  // Gestão. Tudo daqui para baixo é escrita **local** — sobe pelo PowerSync
  // como qualquer lançamento, e portanto funciona offline.
  //
  // Todas checam a permissão antes de escrever, contra o estado do banco local
  // (ver [SpacePermissions]). Não é redundância com a RLS: o
  // `SupabaseConnector` descarta o batch quando o Postgres recusa, então uma
  // escrita sem permissão **não** produziria erro na tela — ela apareceria
  // aplicada e sumiria no checkpoint seguinte, que é o pior desfecho possível.
  // -------------------------------------------------------------------------

  /// Renomeia o espaço.
  Future<Result<void, Failure>> rename({
    required String spaceId,
    required String name,
  });

  /// Troca o papel de um membro.
  ///
  /// Recusa a linha de quem criou o espaço: o dono é admin por construção, e é
  /// isso que garante que todo espaço tenha pelo menos um admin.
  Future<Result<void, Failure>> changeRole({
    required String memberId,
    required SpaceRole role,
  });

  /// Remove alguém do espaço (`status = 'left'`).
  ///
  /// A linha **permanece**: é ela que guarda o histórico de quem lançou o quê,
  /// e é ela que `join_space_by_code` reativa se a pessoa voltar.
  Future<Result<void, Failure>> removeMember(String memberId);

  /// Sai do espaço.
  ///
  /// Quem criou não sai — encerrar é [archive]. Depois de sair, as sync rules
  /// deixam de entregar o bucket e o espaço some do aparelho junto com tudo
  /// que era dele.
  Future<Result<void, Failure>> leave(String spaceId);

  /// Arquiva o espaço: ninguém mais lança, o histórico fica de pé.
  ///
  /// Não é exclusão. Apagar um espaço apagaria o lançamento de outras pessoas,
  /// que não é dado de quem arquiva.
  Future<Result<void, Failure>> archive(String spaceId);
}
