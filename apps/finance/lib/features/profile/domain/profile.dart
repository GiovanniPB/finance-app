import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';

/// O perfil de quem está usando o app.
///
/// Uma linha em `profiles`, criada no cadastro pelo trigger `handle_new_user`
/// (migration `20260714153329`) e entregue pelo bucket `user_owned` das sync
/// rules. **Só o próprio perfil chega ao aparelho** — o de outra pessoa não, e
/// é por isso que o nome de um peer viaja em `space_members.display_name` em
/// vez de ser lido daqui.
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,

    /// Como a pessoa quer ser chamada. Nulo até ela definir no Perfil: nada no
    /// app escreveu esta coluna antes da fatia `nome-de-membro`, e o `signUp`
    /// não envia metadata.
    String? displayName,
  }) = _Profile;

  const Profile._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  factory Profile.fromRow(Map<String, Object?> row) => Profile(
    id: row['id']! as String,
    displayName: row['display_name'] as String?,
  );

  /// Tem nome definido.
  bool get hasName => displayName != null;
}
