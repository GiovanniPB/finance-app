import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../domain/account.dart';

part 'accounts_providers.g.dart';

/// Contas do próprio usuário (offline-first).
///
/// Use este provider em telas de gestão de conta ("minhas contas"). Para
/// escolher uma conta ao lançar num espaço compartilhado, use
/// [spaceAccountsProvider], que inclui as contas vinculadas ao household.
@riverpod
Stream<List<Account>> accounts(Ref ref) =>
    ref.watch(accountsRepositoryProvider).watchOwned();

/// Contas visíveis no espaço ativo: as do usuário mais as que outros membros
/// vincularam àquele household.
@riverpod
Stream<List<Account>> spaceAccounts(Ref ref) {
  final space = ref.watch(activeSpaceProvider);
  if (space == null) return Stream.value(const []);
  return ref.watch(accountsRepositoryProvider).watchForSpace(space.id);
}
