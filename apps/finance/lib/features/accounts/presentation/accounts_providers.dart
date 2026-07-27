import 'package:core/core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/domain/space.dart';
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

/// Espaços aos quais uma conta pode ser vinculada.
///
/// Só `household`: vincular ao espaço pessoal não significaria nada (o dono já
/// vê a própria conta), e `group` compartilha despesa avulsa, não conta — ver
/// ADR 0004. Na Fase 0 esta lista é sempre vazia, então o campo de vínculo não
/// aparece no formulário; ele passa a existir sozinho quando a Fase 2 criar o
/// primeiro household.
@riverpod
List<Space> linkableSpaces(Ref ref) {
  final spaces = ref.watch(spacesProvider).asData?.value ?? const <Space>[];
  return [
    for (final space in spaces)
      if (space.type == SpaceType.household) space,
  ];
}

/// Soma dos saldos das contas do usuário, já com o sinal certo por tipo.
///
/// Cartão de crédito entra negativo (a fatura é dívida), então o número é o
/// líquido das contas cadastradas — não a soma dos números na tela.
///
/// Nulo em dois casos, ambos porque um número seria pior que nenhum:
///  • **Sem conta alguma** — "R$ 0,00" e "nenhuma conta" são estados
///    diferentes, e mostrar zero para o segundo mente.
///  • **Moedas misturadas** — somar BRL com USD não tem resultado. Não
///    acontece hoje (o formulário só cria em BRL), mas pode acontecer quando o
///    Open Finance trouxer conta em outra moeda, e aí é melhor sumir com o
///    total do que exibir um número sem significado.
@riverpod
Money? accountsNetBalance(Ref ref) {
  final accounts = ref.watch(accountsProvider).asData?.value ?? const [];
  if (accounts.isEmpty) return null;

  final currency = accounts.first.currency;
  if (accounts.any((account) => account.currency != currency)) return null;

  return accounts
      .map((account) => account.signedBalance)
      .reduce((total, balance) => total + balance);
}
