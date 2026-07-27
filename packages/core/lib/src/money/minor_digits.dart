/// Entrada de valor dígito a dígito, em unidades mínimas.
///
/// Cada dígito entra **pela direita** (`1` → 0,01; `1`,`4` → 0,14). É o que
/// dispensa a tecla de vírgula nos formulários de dinheiro — e com ela o erro
/// de posicionar o separador decimal, o mais comum em campo de valor.
///
/// Vive no `core` porque mais de um formulário digita valor (registro rápido e
/// limite de orçamento) e a regra precisa ser a mesma nos dois.
abstract final class MinorDigits {
  /// Dez dígitos: até 99.999.999,99. Acima disso é erro de digitação, não caso
  /// de uso — e mantém o valor longe do limite do `int`.
  static const maxDigits = 10;

  /// Acrescenta [digit] pela direita. Ignora o toque quando já está no limite.
  static int append(int amountMinor, int digit) {
    if (digit < 0 || digit > 9) {
      throw ArgumentError.value(digit, 'digit', 'Esperado um dígito de 0 a 9');
    }
    if (amountMinor.toString().length >= maxDigits) return amountMinor;
    return amountMinor * 10 + digit;
  }

  /// Remove o último dígito. Zero permanece zero.
  static int removeLast(int amountMinor) => amountMinor ~/ 10;
}
