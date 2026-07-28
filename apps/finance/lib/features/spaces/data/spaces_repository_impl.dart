import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/space.dart';
import '../domain/space_member.dart';
import '../domain/spaces_repository.dart';

/// Statements em constantes para o teste de guarda rodá-las contra uma view
/// igual à que o PowerSync cria.
///
/// As tabelas locais do PowerSync são **views com triggers `INSTEAD OF`**, e o
/// SQLite recusa construções que uma tabela aceitaria — foi assim que o UPSERT
/// de orçamento passou meses quebrado com o teste verde.
abstract final class SpacesSql {
  static const watchAll = 'SELECT * FROM spaces ORDER BY created_at';

  static const watchById = 'SELECT * FROM spaces WHERE id = ? LIMIT 1';

  static const watchMembers =
      "SELECT * FROM space_members WHERE space_id = ? AND status = 'active' "
      'ORDER BY joined_at';

  static const insertSpace =
      'INSERT INTO spaces (id, space_type, name, owner_id, privacy_policy, '
      'status, settlement_currency, archived_at, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  static List<Object?> insertSpaceParams(Map<String, Object?> cols) => [
    cols['id'],
    cols['space_type'],
    cols['name'],
    cols['owner_id'],
    cols['privacy_policy'],
    cols['status'],
    cols['settlement_currency'],
    cols['archived_at'],
    cols['created_at'],
    cols['updated_at'],
  ];

  static const insertMember =
      'INSERT INTO space_members (id, space_id, user_id, role, status, '
      'share_percentage, joined_at, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)';

  static List<Object?> insertMemberParams(Map<String, Object?> cols) => [
    cols['id'],
    cols['space_id'],
    cols['user_id'],
    cols['role'],
    cols['status'],
    cols['share_percentage'],
    cols['joined_at'],
    cols['created_at'],
    cols['updated_at'],
  ];
}

/// Implementação sobre o PowerSync (SQL bruto), mais duas RPCs no Postgres.
///
/// Depende de [SqliteConnection] (e não de `PowerSyncDatabase`, que é `base`)
/// para permitir teste com mocks.
class SpacesRepositoryImpl implements SpacesRepository {
  SpacesRepositoryImpl({
    required this.db,
    required this.supabase,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? DateTime.now,
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('SpacesRepository');

  final SqliteConnection db;
  final SupabaseClient supabase;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  @override
  Stream<List<Space>> watchAll() => db
      .watch(SpacesSql.watchAll)
      .map((results) => results.map(Space.fromRow).toList());

  @override
  Stream<Space?> watchById(String id) => db
      .watch(SpacesSql.watchById, parameters: [id])
      .map((results) => results.isEmpty ? null : Space.fromRow(results.first));

  @override
  Stream<List<SpaceMember>> watchMembers(String spaceId) => db
      .watch(SpacesSql.watchMembers, parameters: [spaceId])
      .map((results) => results.map(SpaceMember.fromRow).toList());

  @override
  Future<Result<Space, Failure>> createShared({
    required SpaceType type,
    required String name,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(AuthFailure('Nenhuma sessão ativa para criar espaço.'));
    }

    // O Espaço Pessoal nasce no signup e é um por usuário (PRD §4.3). A RLS
    // deixaria passar um segundo, então quem segura a invariante é isto.
    if (type == SpaceType.personal) {
      return const Err(
        ValidationFailure('O Espaço Pessoal é criado no cadastro.'),
      );
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return const Err(ValidationFailure('Dê um nome para o espaço.'));
    }

    final timestamp = _now();
    final space = Space(
      id: _genId(),
      type: type,
      name: trimmedName,
      ownerId: userId,
      // Casal é transparência total; grupo só expõe o que foi lançado nele
      // (PRD §4.2). A política nasce do tipo em vez de ser perguntada: são
      // regras opostas, e oferecer a escolha convidaria a criar um household
      // sem transparência, que é um tipo que não existe.
      privacy: type == SpaceType.household
          ? SpacePrivacy.fullTransparency
          : SpacePrivacy.sharedOnly,
      status: SpaceStatus.active,
      settlementCurrency: Money.brl,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final member = SpaceMember(
      id: _genId(),
      spaceId: space.id,
      userId: userId,
      role: SpaceRole.admin,
      status: MembershipStatus.active,
      joinedAt: timestamp,
    );

    try {
      // As duas linhas na **mesma** transação: um espaço sem membership é um
      // espaço que o próprio dono deixa de enxergar assim que o app reinicia,
      // porque as sync rules bucketizam por membership.
      await db.writeTransaction((tx) async {
        await tx.execute(
          SpacesSql.insertSpace,
          SpacesSql.insertSpaceParams(space.toColumns()),
        );
        await tx.execute(
          SpacesSql.insertMember,
          SpacesSql.insertMemberParams(member.toColumns()),
        );
      });
      return Ok(space);
    } on Exception catch (e, st) {
      _log.severe('Falha ao criar espaço', e, st);
      return const Err(DatabaseFailure('Não foi possível criar o espaço.'));
    }
  }

  @override
  Future<Result<String, Failure>> inviteCode(String spaceId) async {
    try {
      final code = await supabase.rpc<dynamic>(
        'space_invite_code',
        params: {'_space_id': spaceId},
      );
      if (code is! String || code.isEmpty) {
        return const Err(
          DatabaseFailure('O servidor não devolveu um código de convite.'),
        );
      }
      return Ok(code);
    } on PostgrestException catch (e, st) {
      _log.warning('Falha ao gerar convite', e, st);
      // A RPC recusa com mensagem em português e já pensada para a tela
      // (sem permissão, espaço arquivado). Repassá-la é melhor do que trocá-la
      // por um genérico que esconde qual das duas aconteceu.
      return Err(DatabaseFailure(e.message));
    } on Exception catch (e, st) {
      _log.severe('Falha ao gerar convite', e, st);
      return const Err(
        NetworkFailure('Sem conexão para gerar o convite agora.'),
      );
    }
  }

  @override
  Future<Result<String, Failure>> joinByCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const Err(ValidationFailure('Digite o código do convite.'));
    }

    try {
      final spaceId = await supabase.rpc<dynamic>(
        'join_space_by_code',
        params: {'_code': trimmed},
      );
      if (spaceId is! String || spaceId.isEmpty) {
        return const Err(DatabaseFailure('Não foi possível entrar no espaço.'));
      }
      return Ok(spaceId);
    } on PostgrestException catch (e, st) {
      _log.warning('Falha ao entrar com código', e, st);
      return Err(ValidationFailure(e.message));
    } on Exception catch (e, st) {
      _log.severe('Falha ao entrar com código', e, st);
      return const Err(
        NetworkFailure('Sem conexão para entrar no espaço agora.'),
      );
    }
  }
}
