import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../domain/profile.dart';

part 'profile_providers.g.dart';

/// O perfil de quem está usando o app, reativo.
///
/// `null` no dado significa "a linha ainda não chegou pelo bucket
/// `user_owned`" — diferente de `AsyncLoading`, que é "o stream ainda não
/// emitiu". A tela precisa dos dois estados: um convida a definir o nome, o
/// outro mostra que está carregando.
@riverpod
Stream<Profile?> myProfile(Ref ref) =>
    ref.watch(profileRepositoryProvider).watchMine();

/// Só o nome, para quem não precisa do resto.
///
/// A lista de membros usa este provider em vez de `space_members.display_name`
/// para a **própria** linha: a coluna de lá é cópia mantida por trigger no
/// Postgres, e entre salvar o nome e o round-trip completar ela ainda tem o
/// valor velho. Ver o cabeçalho de `MemberCopy`.
@riverpod
String? myDisplayName(Ref ref) =>
    ref.watch(myProfileProvider).asData?.value?.displayName;
