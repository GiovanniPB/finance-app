import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/presentation/accounts_providers.dart';
import '../domain/open_finance_connection.dart';

part 'open_finance_providers.g.dart';

/// Conexões bancárias do usuário (offline-first).
@riverpod
Stream<List<OpenFinanceConnection>> openFinanceConnections(Ref ref) =>
    ref.watch(openFinanceRepositoryProvider).watchAll();

/// Quantas contas cada conexão trouxe, por id de conexão.
///
/// Existe porque a lista de bancos precisa dizer o que a conexão **entregou** —
/// "Itaú · 2 contas" responde a pergunta que o usuário faz ao olhar a tela.
/// Deriva de `accounts` em vez de guardar um contador: contador que precisa ser
/// igual a uma contagem desincroniza offline, e é a mesma razão pela qual não
/// existe `savings_goals.current_amount` (ADR 0007).
@riverpod
Map<String, int> connectionAccountCounts(Ref ref) {
  final accounts = ref.watch(accountsProvider).asData?.value ?? const [];
  final counts = <String, int>{};
  for (final account in accounts) {
    final connectionId = account.connectionId;
    if (connectionId == null) continue;
    counts[connectionId] = (counts[connectionId] ?? 0) + 1;
  }
  return counts;
}

/// Conexões que precisam de ação do usuário para voltar a sincronizar.
///
/// A aba Perfil usa isto para destacar o que está parado. `outdated` fica de
/// fora (ver [ConnectionStatus.needsUserAction]): a Pluggy costuma se recuperar
/// na próxima janela de auto-sync, e cobrar ação para algo que se resolve
/// sozinho treina o usuário a ignorar o aviso.
@riverpod
List<OpenFinanceConnection> connectionsNeedingAction(Ref ref) {
  final connections =
      ref.watch(openFinanceConnectionsProvider).asData?.value ?? const [];
  return connections.where((c) => c.status.needsUserAction).toList();
}

/// Contas que vieram de Open Finance.
///
/// Separado de [accountsProvider] porque as duas naturezas de saldo não se
/// misturam: em conta conectada a Pluggy é dona de `current_balance_minor`
/// (ADR 0005), e editá-lo à mão seria desfeito na próxima sincronização.
@riverpod
List<Account> openFinanceAccounts(Ref ref) {
  final accounts = ref.watch(accountsProvider).asData?.value ?? const [];
  return accounts.where((a) => a.isFromOpenFinance).toList();
}
