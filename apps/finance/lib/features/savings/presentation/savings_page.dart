import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../spaces/presentation/spaces_providers.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/savings_goal.dart';
import 'goal_card.dart';
import 'goal_detail_page.dart';
import 'goal_form_sheet.dart';
import 'goal_icons.dart';
import 'savings_providers.dart';

/// Aba Poupança — o Pilar 3 (PRD §11.2).
///
/// A aba se chama **Poupança**, e não "Social" como o mapa de navegação do PRD
/// (§11.1) previa: o feed, os amigos e os desafios são Fase 3, e um rótulo que
/// promete o que não existe é o que os pilares 2 e 3 do onboarding evitam de
/// propósito. Quando a camada social existir, ela entra aqui.
///
/// O **momento alto** é o total guardado, não o progresso de nenhuma meta em
/// particular: é o número que responde "estou poupando?" antes de qualquer
/// detalhe.
class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(activeSpaceProvider);
    if (space == null) return const _WaitingSync();

    final progress = ref.watch(goalProgressListProvider);
    final paused = ref.watch(pausedGoalsProvider);

    // O estado vazio precisa das duas listas: com todas as metas pausadas,
    // `progress` fica vazia, e sair por aqui esconderia metas que existem —
    // pausar viraria um esconder sem volta.
    if (progress.isEmpty && paused.isEmpty) return const _NoGoalsYet();

    final month = ref.watch(focusedMonthProvider);
    final total = ref.watch(savingsTotalProvider);
    final monthTotal = ref.watch(savingsMonthTotalProvider);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              _Header(spaceName: space.name),
              // Sem meta ativa não há momento alto: um "R$ 0,00" em 40px com
              // metas apenas pausadas anunciaria fracasso onde houve uma
              // escolha deliberada de pausar.
              if (progress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.xl,
                    AppSpacing.screenGutter,
                    AppSpacing.xxl,
                  ),
                  child: BalanceHeader(
                    label: _totalLabel(progress.length),
                    amount: total ?? const Money.zero(),
                    caption: monthTotal.isZero
                        ? 'Nada guardado em ${monthLabel(month)} ainda'
                        : '${monthTotal.format()} em ${monthLabel(month)}',
                  ),
                )
              else
                const SizedBox(height: AppSpacing.xl),
              _SectionTitle(
                title: 'Suas metas',
                onNew: () => GoalFormSheet.show(context),
              ),
              if (progress.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.md,
                  ),
                  child: Text(
                    'Nenhuma meta ativa — todas estão pausadas.',
                    key: const Key('all_goals_paused'),
                    style: context.texts.bodySmall?.copyWith(
                      color: context.tokens.textMuted,
                    ),
                  ),
                ),
              for (final item in progress)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.md,
                  ),
                  child: GoalCard(
                    key: Key('goal_card_${item.goal.id}'),
                    progress: item,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GoalDetailPage(goalId: item.goal.id),
                      ),
                    ),
                  ),
                ),
              if (paused.isNotEmpty) _PausedSection(goals: paused),
            ],
          ),
        ),
        // A lista termina sob a bottom nav; sem o desvanecimento o último card
        // aparece cortado e lê como defeito de renderização.
        const ScrollEdgeFade(),
      ],
    );
  }

  /// "Guardado em 3 metas" — o plural precisa concordar, e com uma meta só a
  /// contagem não informa nada que a lista abaixo já não diga.
  String _totalLabel(int count) =>
      count == 1 ? 'Guardado nesta meta' : 'Guardado em $count metas';
}

class _Header extends StatelessWidget {
  const _Header({required this.spaceName});

  final String spaceName;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      AppSpacing.sm,
      AppSpacing.screenGutter,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Espaço ativo', style: context.texts.labelSmall),
        Text(spaceName, style: context.texts.titleMedium),
      ],
    ),
  );
}

/// Título da seção com a ação de criar meta.
///
/// A ação fica **no cabeçalho**, não no fim da lista e não num FAB flutuante.
/// Com três metas a lista já enche a tela, então uma ação no fim é uma ação que
/// não se vê; e o FAB de "Novo limite" é o único componente do app que lê como
/// Material padrão — não vale repetir o erro numa tela nova.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.onNew});

  final String title;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      0,
      AppSpacing.screenGutter,
      AppSpacing.md,
    ),
    child: Row(
      children: [
        Expanded(child: Text(title, style: context.texts.titleSmall)),
        AppButton(
          key: const Key('new_goal'),
          label: 'Nova meta',
          icon: Icons.add,
          variant: AppButtonVariant.ghost,
          expand: false,
          onPressed: onNew,
        ),
      ],
    ),
  );
}

/// As metas pausadas, no fim da lista.
///
/// **Sem barra de progresso e sem valor.** Meta pausada não tem ritmo a
/// comparar nem prazo a cobrar, e desenhar a barra aqui seria a cobrança que
/// pausar existe para calar. A seção é só o caminho de volta: tocar abre o
/// detalhe, e de lá o "Editar" tem o interruptor para retomar.
class _PausedSection extends StatelessWidget {
  const _PausedSection({required this.goals});

  final List<SavingsGoal> goals;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.xl,
          AppSpacing.screenGutter,
          AppSpacing.md,
        ),
        child: Text(
          goals.length == 1
              ? '1 meta pausada'
              : '${goals.length} metas pausadas',
          style: context.texts.titleSmall?.copyWith(
            color: context.tokens.textMuted,
          ),
        ),
      ),
      for (final goal in goals)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            0,
            AppSpacing.screenGutter,
            AppSpacing.sm,
          ),
          child: _PausedGoalRow(goal: goal),
        ),
    ],
  );
}

class _PausedGoalRow extends StatelessWidget {
  const _PausedGoalRow({required this.goal});

  final SavingsGoal goal;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: tokens.surfaceSunken,
      borderRadius: AppRadii.brLg,
      child: InkWell(
        key: Key('paused_goal_${goal.id}'),
        borderRadius: AppRadii.brLg,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GoalDetailPage(goalId: goal.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(Icons.pause_rounded, size: 18, color: tokens.textMuted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  goal.name,
                  style: context.texts.bodyMedium?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: tokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado vazio: ocupa a tela toda e carrega a única ação.
///
/// **Sem o momento alto zerado.** Um "R\$ 0,00" em 40px seria a pior primeira
/// impressão possível de um recurso de poupança — anuncia fracasso antes de
/// haver o que medir.
class _NoGoalsYet extends StatelessWidget {
  const _NoGoalsYet();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xxxl),
    child: Center(
      child: AppEmptyState(
        icon: GoalIcons.tab,
        title: 'Nenhuma meta ainda',
        message:
            'Uma meta transforma "vou tentar guardar" em um número com '
            'progresso visível. Comece por um objetivo, um valor fixo por mês '
            'ou uma fatia da sua renda.',
        actionLabel: 'Criar primeira meta',
        onAction: () => GoalFormSheet.show(context),
      ),
    ),
  );
}

class _WaitingSync extends StatelessWidget {
  const _WaitingSync();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.screenGutter),
    child: Center(
      child: AppEmptyState(
        icon: Icons.sync,
        title: 'Sincronizando',
        message: 'Suas metas aparecem assim que o espaço chegar.',
      ),
    ),
  );
}
