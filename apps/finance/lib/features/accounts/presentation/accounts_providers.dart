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

/// A única conta do espaço, quando é uma só. Nulo quando são zero ou várias.
///
/// É o padrão do registro rápido: com uma conta só, todo lançamento vem dela, e
/// perguntar custaria um toque para uma resposta que já se sabe. Com duas ou
/// mais não há palpite honesto, e o campo fica vazio.
///
/// Vive num provider, e não espalhado pela tela e pelo controller, porque os
/// dois precisam da **mesma** resposta: o chip que aparece marcado tem de ser a
/// conta que o Salvar grava.
@riverpod
String? soleAccountId(Ref ref) {
  final accounts = ref.watch(spaceAccountsProvider).asData?.value ?? const [];
  return accounts.length == 1 ? accounts.single.id : null;
}

/// Nome da conta por id, para a lista de lançamentos — **vazio quando há uma
/// conta só**.
///
/// Com uma conta, dizer "Nubank" em toda linha não distingue nada: distingue
/// quando existe de onde escolher. A regra vive aqui, e não em cada tela, para
/// a lista do mês e a atividade recente nunca discordarem.
@riverpod
Map<String, String> accountLabels(Ref ref) {
  final accounts = ref.watch(spaceAccountsProvider).asData?.value ?? const [];
  if (accounts.length < 2) return const {};

  return {for (final account in accounts) account.id: account.name};
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
