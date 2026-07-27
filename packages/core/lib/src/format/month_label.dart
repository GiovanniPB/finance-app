const _monthNames = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// Nome do mês em pt-BR, com o ano quando não é o corrente.
///
/// Omitir o ano do mês corrente é deliberado: "julho" é como se fala do mês em
/// que se está, e repetir o ano em toda tela vira ruído. Meses de outros anos
/// levam o ano justamente porque aí a informação passa a importar.
///
/// [today] existe para o teste fixar o "ano corrente".
String monthLabel(DateTime month, {DateTime? today}) {
  final name = _monthNames[month.month - 1];
  final currentYear = (today ?? DateTime.now()).year;
  return month.year == currentYear ? name : '$name de ${month.year}';
}
