import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/goal_progress.dart';
import 'goal_copy.dart';
import 'goal_icons.dart';

/// Uma meta na lista de Poupança.
///
/// Card próprio por meta, em vez de linhas dentro de um card único como na
/// barra de orçamento da home: aqui cada item carrega barra e frase de status,
/// e o progresso **é** o conteúdo da tela. O ritmo generoso é deliberado — a
/// mesma escala de espaçamento comprime na lista de transações e respira aqui.
class GoalCard extends StatelessWidget {
  const GoalCard({required this.progress, this.onTap, super.key});

  final GoalProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final goal = progress.goal;
    final pending = GoalCopy.pending(progress);

    return Material(
      color: context.colors.surfaceContainerLow,
      borderRadius: AppRadii.brXl,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.brXl,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadii.brXl,
            border: Border.all(color: tokens.hairline),
            boxShadow: tokens.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategorySwatch.brand(icon: GoalIcons.forType(goal.type)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          goal.type.label.toUpperCase(),
                          style: context.texts.labelSmall?.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _Trailing(progress: progress),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  MoneyText(
                    progress.contributed,
                    size: MoneySize.large,
                    withSymbol: true,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      GoalCopy.target(progress),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.moneySmall.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SavingsProgress(
                ratio: progress.ratio,
                paceRatio: progress.paceRatio,
                semanticLabel: 'Progresso de ${goal.name}',
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                GoalCopy.status(progress),
                style: context.texts.bodySmall?.copyWith(
                  // Meta concluída ganha a marca no texto; o resto fica neutro.
                  // Nenhum estado desta linha usa âmbar ou vermelho.
                  color: progress.isComplete
                      ? tokens.brandText
                      : tokens.textMuted,
                ),
              ),
              if (pending != null) ...[
                const SizedBox(height: AppSpacing.md),
                _PendingBanner(label: pending),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Há aporte detectado esperando o seu sim", no card da meta.
///
/// **Superfície de poço, nunca âmbar** — a mesma escolha da linha pendente no
/// detalhe da meta: âmbar é atenção de orçamento (RN-1.3), e aqui não há nada
/// errado, só algo a decidir. Sem essa linha o aporte detectado só existiria
/// para quem abrisse a meta certa por conta própria.
class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      key: const Key('goal_card_pending'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: AppRadii.brMd,
      ),
      child: Row(
        children: [
          Icon(
            Icons.done_all,
            size: AppSpacing.md,
            color: tokens.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: context.texts.labelSmall?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Percentual, ou o selo quando a meta fechou.
///
/// O percentual é **`textMuted`, nunca colorido**: em orçamento a cor do
/// percentual carrega o limiar de 80%/100% (RN-1.3), mas meta não tem limiar —
/// o número serve de leitura, não de aviso.
class _Trailing extends StatelessWidget {
  const _Trailing({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    if (progress.isComplete) return const CompletionSeal();

    // Sem base de renda não há percentual honesto a mostrar: a frase de status
    // explica o estado, e um "0%" aqui seria uma afirmação falsa sobre esforço.
    if (progress.needsIncome) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Text(
        '${progress.percent}%',
        style: AppTypography.moneySmall.copyWith(
          color: context.tokens.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
