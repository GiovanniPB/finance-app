import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settlement.freezed.dart';

/// O saldo líquido de uma pessoa nas despesas divididas de um espaço.
///
/// Positivo é ter a receber; negativo é dever. A soma dos saldos de um espaço é
/// **sempre zero** — cada centavo que alguém adiantou é centavo que outro deve.
/// [Settlement.from] verifica isso em `assert`: se não fecha, o defeito está na
/// leitura do banco, não no rateio.
@freezed
abstract class MemberBalance with _$MemberBalance {
  const factory MemberBalance({
    required String userId,

    /// Quanto essa pessoa pagou menos quanto ela deve.
    required Money net,
  }) = _MemberBalance;

  const MemberBalance._();

  /// Adiantou mais do que a própria parte — tem a receber.
  bool get isCreditor => net.isPositive;

  /// Deve mais do que pagou.
  bool get isDebtor => net.isNegative;

  bool get isSettled => net.isZero;
}

/// Uma transferência que zera parte do saldo do grupo.
///
/// Não é um lançamento: é a **proposta** de quem paga quem. A linha só nasce ao
/// registrar o acerto (ver `SettlementRepository.settle`).
@freezed
abstract class SettlementTransfer with _$SettlementTransfer {
  const factory SettlementTransfer({
    required String fromUserId,
    required String toUserId,
    required Money amount,
  }) = _SettlementTransfer;

  const SettlementTransfer._();

  /// Se [userId] está numa das duas pontas — o que decide quem pode registrar
  /// o acerto (só quem está na linha).
  bool involves(String userId) => fromUserId == userId || toUserId == userId;
}

/// O estado de "quem deve a quem" de um espaço.
///
/// ─────────────────────────────────────────────────────────────────────────
/// NADA DIVIDIDO, TUDO QUITE E MOEDA DIVERGENTE SÃO TRÊS ESTADOS, NÃO UM
///
/// Os três chegam à tela com [transfers] vazia, e a UI precisa dizer coisas
/// diferentes em cada um: "nenhuma despesa dividida" ensina onde dividir; "está
/// tudo quite" é resultado e não pode parecer defeito; moeda divergente é uma
/// recusa de somar. Colapsar os três num "vazio" só faria a pessoa achar que a
/// divisão não funcionou.
@freezed
abstract class Settlement with _$Settlement {
  const factory Settlement({
    /// Cada pessoa que apareceu no rateio, inclusive quem está com saldo zero e
    /// quem já saiu do espaço.
    required List<MemberBalance> balances,

    /// O que zera o grupo, em no máximo `n−1` passos. Vazia nos três estados
    /// descritos acima.
    required List<SettlementTransfer> transfers,

    /// Quantos lançamentos divididos entraram na conta. É o que separa "nada
    /// dividido" de "tudo quite".
    required int splitCount,

    /// As moedas encontradas. Mais de uma e o agregado se recusa a somar
    /// (invariante global de `docs/product.md`).
    required Set<String> currencies,
  }) = _Settlement;

  /// Deriva as transferências a partir dos saldos.
  factory Settlement.from({
    required List<MemberBalance> balances,
    required int splitCount,
  }) {
    final currencies = {for (final balance in balances) balance.net.currency};
    final mixed = currencies.length > 1;

    assert(
      mixed || balances.fold<int>(0, (sum, b) => sum + b.net.amountMinor) == 0,
      'A soma dos saldos tem de ser zero; veio '
      '${balances.map((b) => b.net.amountMinor).join(' + ')}',
    );

    return Settlement(
      balances: balances,
      transfers: mixed ? const [] : minimalTransfers(balances),
      splitCount: splitCount,
      currencies: currencies,
    );
  }

  const Settlement._();

  /// Espaço sem nenhuma despesa dividida.
  static const Settlement nothingSplit = Settlement(
    balances: [],
    transfers: [],
    splitCount: 0,
    currencies: {},
  );

  /// Nenhum lançamento dividido no espaço — o estado de todo grupo novo.
  bool get hasNothingSplit => splitCount == 0;

  /// Há divisão, e ela já se cancela.
  bool get isAllSettled =>
      splitCount > 0 && transfers.isEmpty && !isMixedCurrency;

  /// Duas moedas no mesmo espaço: recusa somar em vez de somar errado.
  bool get isMixedCurrency => currencies.length > 1;

  /// O saldo de uma pessoa, ou `null` se ela não participou de rateio nenhum.
  MemberBalance? balanceOf(String userId) {
    for (final balance in balances) {
      if (balance.userId == userId) return balance;
    }
    return null;
  }

  /// As transferências que [userId] pode registrar — as que o envolvem.
  List<SettlementTransfer> transfersInvolving(String userId) =>
      transfers.where((transfer) => transfer.involves(userId)).toList();
}

/// Casa o maior credor com o maior devedor até o grupo zerar.
///
/// ─────────────────────────────────────────────────────────────────────────
/// POR QUE GULOSO, E NÃO O MÍNIMO
///
/// O mínimo verdadeiro de transferências é NP-difícil (reduz a partição de
/// subconjuntos): dá para gastar tempo exponencial procurando subgrupos que já
/// se cancelam entre si. O guloso entrega **no máximo `n−1`** transferências,
/// porque cada passo zera ao menos uma das duas pontas, e isso é o suficiente
/// para um grupo de república. Decisão de 2026-08-01, ADR 0012.
///
/// O preço aceito: pode sair "pague ao Bruno" para quem só gastou com a Carla.
/// É o mesmo incômodo do "simplify debts" do Splitwise.
///
/// ─────────────────────────────────────────────────────────────────────────
/// A ORDEM É ESTÁVEL DE PROPÓSITO
///
/// Empate de valor é desempatado por `userId`. Sem isso a saída dependeria da
/// ordem em que o SQL devolveu as linhas, e o teste passaria por sorte — mesmo
/// tipo de coincidência que fez o recorte de mês deste repo ficar meses errado.
List<SettlementTransfer> minimalTransfers(List<MemberBalance> balances) {
  final currencies = {for (final balance in balances) balance.net.currency};
  if (currencies.length > 1) return const [];
  final currency = currencies.isEmpty ? Money.brl : currencies.first;

  final creditors = [
    for (final balance in balances)
      if (balance.isCreditor) _Pot(balance.userId, balance.net.amountMinor),
  ]..sort(_biggestFirst);
  final debtors = [
    for (final balance in balances)
      if (balance.isDebtor) _Pot(balance.userId, -balance.net.amountMinor),
  ]..sort(_biggestFirst);

  final transfers = <SettlementTransfer>[];
  var credit = 0;
  var debt = 0;

  while (credit < creditors.length && debt < debtors.length) {
    final creditor = creditors[credit];
    final debtor = debtors[debt];
    final amount = creditor.amount < debtor.amount
        ? creditor.amount
        : debtor.amount;

    transfers.add(
      SettlementTransfer(
        fromUserId: debtor.userId,
        toUserId: creditor.userId,
        amount: Money.fromMinor(amount, currency: currency),
      ),
    );

    creditor.amount -= amount;
    debtor.amount -= amount;
    if (creditor.amount == 0) credit++;
    if (debtor.amount == 0) debt++;
  }

  return transfers;
}

/// Uma ponta do casamento, com o valor sendo consumido.
class _Pot {
  _Pot(this.userId, this.amount);

  final String userId;
  int amount;
}

int _biggestFirst(_Pot a, _Pot b) {
  final byAmount = b.amount.compareTo(a.amount);
  return byAmount != 0 ? byAmount : a.userId.compareTo(b.userId);
}
