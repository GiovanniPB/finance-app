import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'transaction.dart';

/// Totais de um mês, derivados de uma lista de transações.
///
/// Não é entidade persistida. Vive no domínio (e não na apresentação) porque a
/// regra de agregação é regra de negócio: o que conta como saída, o que entra
/// no acumulado por categoria, e como o saldo se compõe. Assim a lógica é
/// testável sem Riverpod e sem banco.
///
/// A agregação acontece em Dart em vez de `SUM()` no SQL porque a janela é um
/// mês — dezenas a centenas de linhas. Se a janela crescer para anos, isto vira
/// query agregada.
@immutable
class MonthSummary {
  const MonthSummary({
    required this.income,
    required this.outflow,
    required this.balance,
    required this.spentByCategory,
  });

  /// Calcula a partir de uma lista de transações.
  ///
  /// [income] soma as entradas, [outflow] soma o **módulo** das saídas, e
  /// [balance] é a diferença — positiva quando entrou mais do que saiu.
  /// Transações sem categoria entram no [outflow] mas não em
  /// [spentByCategory], porque não há orçamento a debitar.
  ///
  /// **`transfer` não entra em nenhum dos dois lados**, e isto já foi um bug.
  /// A versão anterior somava em [income] tudo que não era saída, o que era
  /// inofensivo enquanto nada no produto produzia `transfer`. Quando a ingestão
  /// do Open Finance passou a gravar pagamento de fatura como `transfer`, o mês
  /// exibiu **R$ 10.641,79 de "Entradas" que eram dinheiro trocando de bolso**
  /// — visto rodando, com extrato de banco real. Dinheiro que só muda de conta
  /// não é receita nem despesa; o gasto já foi contado quando a compra entrou.
  factory MonthSummary.from(List<Transaction> transactions) {
    var income = const Money.zero();
    var outflow = const Money.zero();
    final byCategory = <String, Money>{};

    for (final transaction in transactions) {
      final absolute = transaction.amount.abs;
      if (transaction.type.isOutflow) {
        outflow += absolute;
        final key = transaction.categoryId;
        if (key != null) {
          byCategory[key] = (byCategory[key] ?? const Money.zero()) + absolute;
        }
      } else if (transaction.type == TransactionType.income) {
        // Casa por tipo, não por "o que sobrou": um tipo novo passa a não
        // contar em nada, em vez de virar receita em silêncio.
        income += absolute;
      }
    }

    return MonthSummary(
      income: income,
      outflow: outflow,
      balance: income - outflow,
      spentByCategory: Map.unmodifiable(byCategory),
    );
  }

  /// Mês sem nenhuma transação.
  static const empty = MonthSummary(
    income: Money.zero(),
    outflow: Money.zero(),
    balance: Money.zero(),
    spentByCategory: {},
  );

  /// Total de entradas (positivo).
  final Money income;

  /// Total de saídas, em módulo (positivo).
  final Money outflow;

  /// Entradas menos saídas. Pode ser negativo.
  final Money balance;

  /// Gasto acumulado por categoria, em módulo. Só considera saídas.
  final Map<String, Money> spentByCategory;

  /// Gasto de uma categoria no mês (zero quando não houve).
  Money spentIn(String categoryId) =>
      spentByCategory[categoryId] ?? const Money.zero();
}
