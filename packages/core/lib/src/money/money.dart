import 'package:meta/meta.dart';

/// Valor monetário imutável representado em **unidades mínimas** (centavos).
///
/// Ver ADR 0006: dinheiro nunca é `double`. Toda aritmética é inteira, evitando
/// erro de ponto flutuante. A moeda ([currency]) é um código ISO-4217;
/// operações entre moedas diferentes lançam [ArgumentError].
@immutable
class Money implements Comparable<Money> {
  /// Cria a partir de unidades mínimas (ex.: `Money.fromMinor(1050)` = R$
  /// 10,50).
  const Money.fromMinor(this.amountMinor, {this.currency = brl});

  /// Cria a partir de um valor "maior" (reais), arredondando para centavos.
  ///
  /// Uso restrito a bordas (entrada manual, ingestão): `10.5` → `1050`.
  factory Money.fromMajor(num major, {String currency = brl}) =>
      Money.fromMinor((major * _minorPerMajor).round(), currency: currency);

  /// Zero na [currency] informada.
  const Money.zero({this.currency = brl}) : amountMinor = 0;

  /// Código ISO-4217 padrão do mercado-alvo.
  static const brl = 'BRL';
  static const _minorPerMajor = 100;
  static const _symbols = {'BRL': r'R$', 'USD': r'US$', 'EUR': '€'};

  /// Quantidade em unidades mínimas (centavos). Pode ser negativa (dívida).
  final int amountMinor;

  /// Código da moeda (ISO-4217).
  final String currency;

  bool get isZero => amountMinor == 0;
  bool get isNegative => amountMinor < 0;
  bool get isPositive => amountMinor > 0;

  /// Valor absoluto, preservando a moeda.
  Money get abs => Money.fromMinor(amountMinor.abs(), currency: currency);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money.fromMinor(amountMinor + other.amountMinor, currency: currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money.fromMinor(amountMinor - other.amountMinor, currency: currency);
  }

  Money operator -() => Money.fromMinor(-amountMinor, currency: currency);

  /// Multiplica por um escalar inteiro (ex.: N parcelas iguais).
  Money operator *(int factor) =>
      Money.fromMinor(amountMinor * factor, currency: currency);

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return amountMinor.compareTo(other.amountMinor);
  }

  /// Reparte este valor proporcionalmente a [ratios], sem perder centavos.
  ///
  /// Usa o método do maior resto: a soma das partes é sempre igual ao total.
  /// Ex.: `Money.fromMinor(1000).allocate([1, 1, 1])` → `[334, 333, 333]`.
  List<Money> allocate(List<int> ratios) {
    if (ratios.isEmpty) {
      throw ArgumentError.value(ratios, 'ratios', 'Não pode ser vazio.');
    }
    final total = ratios.fold(0, (sum, r) => sum + r);
    if (total <= 0) {
      throw ArgumentError.value(ratios, 'ratios', 'Soma deve ser positiva.');
    }

    final shares = List<int>.filled(ratios.length, 0);
    var distributed = 0;
    for (var i = 0; i < ratios.length; i++) {
      shares[i] =
          (amountMinor * ratios[i]) ~/ total; // trunca em direção a zero
      distributed += shares[i];
    }

    // Distribui o resto (1 unidade por vez) nos maiores restos fracionários.
    var remainder = amountMinor - distributed;
    final step = remainder.isNegative ? -1 : 1;
    final byRemainder = List.generate(ratios.length, (i) => i)
      ..sort((a, b) {
        final ra = (amountMinor * ratios[a]) % total;
        final rb = (amountMinor * ratios[b]) % total;
        return rb.abs().compareTo(ra.abs());
      });
    for (var k = 0; remainder != 0; k++) {
      shares[byRemainder[k % ratios.length]] += step;
      remainder -= step;
    }

    return [for (final s in shares) Money.fromMinor(s, currency: currency)];
  }

  /// Divide igualmente em [parts] partes (atalho para [allocate] uniforme).
  List<Money> split(int parts) {
    if (parts <= 0) {
      throw ArgumentError.value(parts, 'parts', 'Deve ser positivo.');
    }
    return allocate(List<int>.filled(parts, 1));
  }

  /// Formata no padrão pt-BR (ex.: `R$ 1.234,56`, `-R$ 10,00`).
  ///
  /// Com [withSymbol] `false`, omite o símbolo da moeda (ex.: `1.234,56`) —
  /// usado em listas densas, onde a moeda do espaço já está implícita e repetir
  /// `R$` em cada linha rouba espaço horizontal sem informar nada.
  String format({bool withSymbol = true}) {
    final cents = amountMinor.abs();
    final major = cents ~/ _minorPerMajor;
    final frac = (cents % _minorPerMajor).toString().padLeft(2, '0');
    final sign = isNegative ? '-' : '';
    final digits = '${_groupThousands(major)},$frac';
    if (!withSymbol) return '$sign$digits';
    final symbol = _symbols[currency] ?? currency;
    return '$sign$symbol $digits';
  }

  static String _groupThousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Operação entre moedas diferentes: $currency vs ${other.currency}.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  @override
  String toString() => 'Money(${format()})';
}
