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

/// Rótulo do dia em pt-BR, com "Hoje" e "Ontem" no lugar da data.
///
/// Os dois dias mais recentes ganham nome porque é assim que se fala deles, e
/// porque são os que mais aparecem: numa lista de gastos do mês, quase tudo é
/// de hoje ou de ontem.
///
/// [today] existe para o teste não depender do relógio.
String formatDayLabel(DateTime date, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final reference = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final difference = reference.difference(target).inDays;

  if (difference == 0) return 'Hoje';
  if (difference == 1) return 'Ontem';

  return '${target.day} de ${_monthNames[target.month - 1]}';
}
