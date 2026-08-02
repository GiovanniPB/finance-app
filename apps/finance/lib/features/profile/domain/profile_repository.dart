import 'package:core/core.dart';

import 'profile.dart';

/// Acesso ao perfil de quem está usando o app.
///
/// ─────────────────────────────────────────────────────────────────────────
/// É `UPDATE`, NUNCA `UPSERT` — E ISSO NÃO É ESTILO
///
/// A linha já existe: o trigger `handle_new_user` a cria no cadastro. E as
/// tabelas locais do PowerSync são **views com triggers `INSTEAD OF`**, onde o
/// SQLite recusa `UPSERT`. Um `INSERT … ON CONFLICT` aqui passaria em mock e
/// falharia no aparelho.
///
/// A contrapartida é que um `UPDATE` sem linha afeta zero e **não dá erro**.
/// Por isso [updateDisplayName] devolve `Err` quando não encontrou nada para
/// atualizar, em vez de fingir sucesso — é o único jeito de a UI distinguir
/// "salvei" de "o perfil ainda não sincronizou".
abstract interface class ProfileRepository {
  /// O perfil do usuário logado. `null` enquanto a linha não chegou pelo
  /// bucket `user_owned`.
  Stream<Profile?> watchMine();

  /// Define o nome, validado e sem espaço nas pontas.
  ///
  /// Recusa nome vazio (ou só de espaços) e nome acima de 120 caracteres — o
  /// mesmo limite que o `check` do Postgres aplica, para a recusa acontecer na
  /// tela e não numa fila de upload que ninguém vê.
  Future<Result<void, Failure>> updateDisplayName(String name);
}
