import 'package:core/core.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile.dart';
import '../domain/profile_repository.dart';

/// Statements em constantes para o teste de guarda rodá-las contra uma view
/// igual à que o PowerSync cria.
///
/// Não há `UPSERT` aqui, e não é omissão: a linha de `profiles` nasce no
/// cadastro pelo trigger `handle_new_user`, e as tabelas locais do PowerSync
/// são views com triggers `INSTEAD OF`, onde o SQLite recusa
/// `INSERT … ON CONFLICT`.
abstract final class ProfileSql {
  static const byId = 'SELECT * FROM profiles WHERE id = ? LIMIT 1';

  static const updateDisplayName =
      'UPDATE profiles SET display_name = ?, updated_at = ? WHERE id = ?';
}

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl({
    required this.db,
    required this.supabase,
    DateTime Function()? now,
    AppLogger? logger,
  }) : _now = now ?? DateTime.now,
       _log = logger ?? AppLogger('ProfileRepository');

  /// O mesmo limite do `check` em `profiles.display_name` e de `spaces.name`.
  /// Recusar aqui é o que faz a mensagem aparecer na tela: offline, a violação
  /// do `check` só apareceria quando a fila de upload subisse, longe de quem
  /// digitou.
  static const maxNameLength = 120;

  final SqliteConnection db;
  final SupabaseClient supabase;
  final DateTime Function() _now;
  final AppLogger _log;

  @override
  Stream<Profile?> watchMine() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value(null);

    return db
        .watch(ProfileSql.byId, parameters: [userId])
        .map(
          (results) => results.isEmpty ? null : Profile.fromRow(results.first),
        );
  }

  @override
  Future<Result<void, Failure>> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Err(ValidationFailure('Digite um nome.'));
    }
    if (trimmed.length > maxNameLength) {
      return const Err(
        ValidationFailure('O nome cabe em $maxNameLength caracteres.'),
      );
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(AuthFailure('Nenhuma sessão ativa para salvar o nome.'));
    }

    try {
      // A existência é conferida ANTES do UPDATE de propósito. Um UPDATE que
      // não casa com nenhuma linha afeta zero e **não levanta erro**: sem esta
      // leitura, quem abrisse o Perfil antes de o bucket `user_owned` entregar
      // o perfil veria "salvo" e nada teria sido salvo.
      final existing = await db.getOptional(ProfileSql.byId, [userId]);
      if (existing == null) {
        return const Err(
          DatabaseFailure(
            'Seu perfil ainda está sincronizando. Tente de novo em instantes.',
          ),
        );
      }

      await db.execute(ProfileSql.updateDisplayName, [
        trimmed,
        _now().toUtc().toIso8601String(),
        userId,
      ]);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao salvar o nome', e, st);
      return Err(DatabaseFailure('Não foi possível salvar o nome.', cause: e));
    }
  }
}
