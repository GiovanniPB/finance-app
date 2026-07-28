import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../../transactions/domain/month_summary.dart';
import '../domain/space.dart';

/// O resumo do espaço: o que ele é, quem está nele, e como anda o mês.
///
/// ─────────────────────────────────────────────────────────────────────────
/// O SALDO NÃO É O MOMENTO ALTO AQUI
///
/// Na home ele é 40px mono, porque a home existe para responder "quanto eu
/// tenho". Esta tela existe para responder "o que é este espaço e quem manda
/// nele" — repetir o tratamento da home faria duas telas competirem pelo mesmo
/// papel e nenhuma vencer. Por isso o valor vem em corpo de texto, com as três
/// informações lado a lado: a comparação entre elas é o conteúdo.
class SpaceSummaryCard extends StatelessWidget {
  const SpaceSummaryCard({
    required this.space,
    required this.memberCount,
    required this.summary,
    super.key,
  });

  final Space space;
  final int memberCount;
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppRadii.brXl,
        border: Border.all(color: tokens.hairline),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _privacyLine(space),
            key: const Key('space_privacy_line'),
            style: context.texts.bodySmall?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Figure(
                label: 'Pessoas',
                value: memberCount.toString(),
                keyName: 'space_people_count',
              ),
              _Figure(
                label: 'Entrou no mês',
                value: summary.income.format(),
                keyName: 'space_month_income',
              ),
              _Figure(
                label: 'Saiu no mês',
                value: summary.outflow.format(),
                keyName: 'space_month_outflow',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A frase de privacidade é o que diferencia os tipos, e ela é a razão de o
  /// tipo não poder ser trocado depois (PRD §4.2 — a migration
  /// `20260728210321` passou a impedir isso no banco).
  static String _privacyLine(Space space) => switch (space.type) {
    SpaceType.group =>
      'Grupo. Cada pessoa vê só o que foi lançado aqui — o resto '
          'da vida financeira de cada um continua privado.',
    SpaceType.household =>
      'Casal. Orçamento e metas em comum, e tudo o que entra '
          'aqui é visível para as duas pessoas.',
    SpaceType.personal =>
      'Pessoal. Só você, e ninguém pode ser convidado para cá.',
  };
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.keyName,
  });

  final String label;
  final String value;
  final String keyName;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.texts.labelSmall?.copyWith(
            color: context.tokens.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          key: Key(keyName),
          style: context.texts.titleSmall,
        ),
      ],
    ),
  );
}
