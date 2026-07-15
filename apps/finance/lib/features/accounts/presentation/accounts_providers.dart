import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../domain/account.dart';

part 'accounts_providers.g.dart';

/// Lista reativa de contas do usuário (offline-first).
@riverpod
Stream<List<Account>> accounts(Ref ref) =>
    ref.watch(accountsRepositoryProvider).watchAll();
