import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/savings_badge.dart';
import 'badge_copy.dart';

/// As conquistas do espaço, na aba Poupança (PRD §8.2).
///
/// ─────────────────────────────────────────────────────────────────────────
/// A BLOQUEADA MOSTRA O CRITÉRIO, NÃO UM CADEADO
///
/// Um selo apagado com cadeado comunica "existe algo aqui" e nada mais — o
/// usuário fica sabendo que perdeu sem saber do quê. Cada conquista bloqueada
/// carrega a frase do que é preciso fazer, o que a transforma de troféu ausente
/// em próximo passo. É a mesma escolha do `GoalCopy.status`: dizer o que falta,
/// não que está faltando.
///
/// A ordem vem de `deriveBadges` — desbloqueadas primeiro, depois as mais
/// próximas —, e por isso a **primeira bloqueada da lista é sempre a próxima
/// alcançável**. Ordenar aqui de novo quebraria isso.
class BadgesSection extends StatelessWidget {
  const BadgesSection({required this.badges, super.key});

  final List<BadgeStatus> badges;

  @override
  Widget build(BuildContext context) {
    final earned = badges.where((b) => b.isEarned).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.xl,
            AppSpacing.screenGutter,
            AppSpacing.md,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Conquistas', style: context.texts.titleMedium),
              Text(
                '$earned de ${badges.length}',
                key: const Key('badges_count'),
                style: AppTypography.moneySmall.copyWith(
                  color: context.tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            itemCount: badges.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, index) => _BadgeTile(status: badges[index]),
          ),
        ),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.status});

  final BadgeStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final badge = status.badge;
    final earned = status.isEarned;
    final remaining = BadgeCopy.remaining(status);

    return Semantics(
      label: earned
          ? 'Conquista desbloqueada: ${badge.label}'
          : 'Conquista bloqueada: ${badge.label}. ${badge.criterion}',
      excludeSemantics: true,
      child: Container(
        key: Key('badge_${badge.key}'),
        width: 148,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: earned
              ? tokens.brandSubtle
              : context.colors.surfaceContainerLow,
          borderRadius: AppRadii.brLg,
          border: Border.all(
            color: earned ? tokens.brandBorder : tokens.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              earned ? Icons.military_tech : Icons.military_tech_outlined,
              color: earned ? tokens.brandText : tokens.textMuted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              badge.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelLarge?.copyWith(
                color: earned ? tokens.brandText : tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Expanded(
              child: Text(
                badge.criterion,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelSmall?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ),
            // O que falta vai em **texto**, não em barra. `SavingsProgress`
            // seria o reuso óbvio e é o errado: aquela barra significa "meta"
            // no sistema visual, e repeti-la em sete selos gastaria o sinal que
            // a torna legível no card da meta. Num tile de 148px o número
            // informa mais que o traço, e diz o que a barra não diz.
            if (remaining != null)
              Text(
                remaining,
                style: AppTypography.moneySmall.copyWith(
                  color: tokens.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
