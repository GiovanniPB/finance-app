/// Data no formato de uma coluna `date` do Postgres (`YYYY-MM-DD`), sem hora.
///
/// Existe porque gravar `toIso8601String()` numa coluna `date` manda hora e
/// fuso junto, e o PowerSync guarda tudo como texto: a hora sobrevive no SQLite
/// local e depois some no Postgres, então a mesma linha lê diferente antes e
/// depois do sync. Cortar a hora na fronteira mantém as duas leituras iguais.
///
/// Usa os componentes **locais** de propósito: uma data de calendário escolhida
/// pelo usuário ("1º de julho") é aquela data no fuso dele, e converter para
/// UTC a jogaria para o dia anterior em qualquer fuso a oeste de Greenwich.
String isoDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
