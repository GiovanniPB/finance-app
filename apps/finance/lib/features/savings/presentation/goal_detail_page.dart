import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../../accounts/presentation/accounts_providers.dart';
import '../domain/goal_progress.dart';
import '../domain/savings_contribution.dart';
import '../domain/savings_goal.dart';
import 'contribution_sheet.dart';
import 'goal_copy.dart';
import 'goal_form_sheet.dart';
import 'goal_icons.dart';
import 'savings_providers.dart';

/// Detalhe de uma meta: progresso, projeção e histórico de contribuições.
///
/// O **momento alto** é o quanto já foi guardado, não o quanto falta. A meta
/// existe para dar visibilidade a um hábito, e abrir a tela com o número que
/// falta transformaria progresso em dívida.
class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({required this.goalId, super.key});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(goalProgressProvider(goalId));

    // A meta deixou de existir — é o que acontece nesta própria tela depois de
    // excluir. Sair é a única leitura honesta do estado.
    if (progress == null) return const _GoalGone();

    final goal = progress.goal;
    final contributions = ref.watch(goalContributionsProvider(goalId));

    // Pausada, a tela mostra o que já foi guardado e cala o que cobra: sem
    // marca de ritmo, sem "faltam R$ X até tal data", sem projeção. É o detalhe
    // de uma meta que continua alcançável — a seção de pausadas da aba leva até
    // aqui, e o "Editar" tem o interruptor para retomar.
    final isPaused = goal.status == SavingsGoalStatus.paused;

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.name),
        actions: [
          TextButton(
            key: const Key('goal_edit'),
            onPressed: () async {
              final changed = await GoalFormSheet.show(
                context,
                editing: goal,
              );
              // Excluir pela folha fecha o detalhe junto: a tela que resta não
              // tem mais assunto.
              if ((changed ?? false) && context.mounted) {
                final gone = ref.read(goalProgressProvider(goalId)) == null;
                if (gone) Navigator.of(context).pop();
              }
            },
            child: const Text('Editar'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                _Hero(progress: progress),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.xxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SavingsProgress(
                        ratio: progress.ratio,
                        // Meta pausada não tem marca de ritmo: o tick diz "o
                        // prazo esperava você aqui", e essa é exatamente a
                        // cobrança que pausar existe para calar. A barra fica —
                        // quanto já foi guardado é informação, não pressão.
                        paceRatio: isPaused ? null : progress.paceRatio,
                        semanticLabel: 'Progresso de ${goal.name}',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isPaused
                            // Nem "faltam R$ X", nem "até 5 de março": pausada,
                            // a meta só diz que está pausada e como voltar.
                            ? 'Pausada · retome em Editar'
                            : [
                                GoalCopy.pace(progress),
                                GoalCopy.status(progress),
                              ].nonNulls.join(' · '),
                        key: const Key('goal_status_line'),
                        style: context.texts.bodySmall?.copyWith(
                          color: context.tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // A projeção ("neste ritmo você fecha em outubro") pressupõe um
                // ritmo que a meta pausada não tem.
                if (!isPaused) _Projection(progress: progress),
                _Contributions(
                  contributions: contributions,
                  currency: goal.currency,
                ),
              ],
            ),
          ),
          const ScrollEdgeFade(),
          _Footer(progress: progress),
        ],
      ),
    );
  }
}

/// O acumulado em 40px, com o alvo abaixo em texto quieto.
class _Hero extends StatelessWidget {
  const _Hero({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.lg,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategorySwatch.brand(
                icon: GoalIcons.forType(progress.goal.type),
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                progress.goal.type.label.toUpperCase(),
                style: context.texts.labelSmall?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MoneyText(
            progress.contributed,
            size: MoneySize.balance,
            withSymbol: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            progress.needsIncome
                ? GoalCopy.target(progress)
                : '${GoalCopy.target(progress)} · ${progress.percent}%',
            style: AppTypography.moneySmall.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Projeção em prosa (RN-3.3).
///
/// Só aparece quando há o que projetar. Uma seção "Projeção" vazia, ou com um
/// "—", ocuparia espaço para dizer nada.
class _Projection extends ConsumerWidget {
  const _Projection({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projection = GoalCopy.projection(progress);
    final required = GoalCopy.requiredMonthly(progress);
    final accountName = _accountName(ref);

    if (projection == null && required == null && accountName == null) {
      return const SizedBox.shrink();
    }

    final tokens = context.tokens;
    final deadline = progress.goal.targetDate;
    final deadlineLabel = deadline == null
        ? null
        : monthLabel(
            DateTime(deadline.year, deadline.month),
            today: progress.now,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        0,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Projeção', style: context.texts.titleSmall),
              ),
              if (deadlineLabel != null)
                Text(
                  'alvo: $deadlineLabel',
                  style: context.texts.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: AppRadii.brXl,
              border: Border.all(color: tokens.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (projection != null || required != null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (projection != null)
                          Text(
                            projection,
                            key: const Key('goal_projection'),
                            style: context.texts.bodySmall?.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                        if (required != null) ...[
                          if (projection != null)
                            const SizedBox(height: AppSpacing.md),
                          // A frase acionável fica em texto primário: é a única
                          // do bloco que diz o que fazer.
                          Text(
                            required,
                            key: const Key('goal_required_monthly'),
                            style: context.texts.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (accountName != null)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: tokens.hairline),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_balance_outlined,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // Expandido com elipse: nome de conta é texto livre do
                        // usuário, e "Conta corrente conjunta do Nubank" não
                        // pode vazar a borda do card.
                        Expanded(
                          child: Text(
                            'Guardando em $accountName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodySmall?.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Nome da conta vinculada. Nulo quando a meta não tem conta, ou quando a
  /// conta foi excluída (`on delete set null` no Postgres).
  String? _accountName(WidgetRef ref) {
    final accountId = progress.goal.linkedAccountId;
    if (accountId == null) return null;

    final accounts = ref.watch(accountsProvider).asData?.value ?? const [];
    return accounts.where((a) => a.id == accountId).firstOrNull?.name;
  }
}

/// Histórico de contribuições, pendentes no topo.
class _Contributions extends ConsumerWidget {
  const _Contributions({required this.contributions, required this.currency});

  final List<SavingsContribution> contributions;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;

    if (contributions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        child: Text(
          'Nenhuma contribuição ainda. Use "Guardei um valor" quando separar '
          'dinheiro para esta meta.',
          key: const Key('goal_no_contributions'),
          style: context.texts.bodySmall?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Contribuições', style: context.texts.titleSmall),
              ),
              Text(
                _countLabel(contributions.length),
                style: context.texts.bodySmall?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          // A dica existe porque o toque na linha só faz uma coisa, e ela é
          // destrutiva: sem dizer, ninguém descobre — e quem descobrisse por
          // acidente levaria um susto.
          Text(
            'Toque numa contribuição para removê-la.',
            key: const Key('goal_contributions_hint'),
            style: context.texts.labelSmall?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: AppRadii.brXl,
              border: Border.all(color: tokens.hairline),
            ),
            child: Column(
              children: [
                for (var i = 0; i < contributions.length; i++)
                  _ContributionRow(
                    contribution: contributions[i],
                    isLast: i == contributions.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _countLabel(int count) =>
      count == 1 ? '1 no total' : '$count no total';
}

/// Uma linha do histórico. Tocar nela oferece remover.
///
/// "Tocar e confirmar" em vez de arrastar: não existe `Dismissible` em nenhum
/// lugar do app, e inventar um gesto só aqui faria esta lista se comportar
/// diferente de todas as outras. O diálogo é a mesma forma de excluir
/// lançamento, conta e meta.
class _ContributionRow extends ConsumerWidget {
  const _ContributionRow({required this.contribution, required this.isLast});

  final SavingsContribution contribution;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final pending = contribution.isPending;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      // `Material` + `InkWell` em vez de `GestureDetector`: sem ele o toque não
      // dá retorno nenhum, e ação destrutiva sem feedback parece não ter
      // registrado.
      child: Material(
        // Pendente ganha superfície de poço — **não âmbar**. Âmbar é atenção de
        // orçamento; aqui não há nada errado, só algo a confirmar.
        color: pending ? tokens.surfaceSunken : Colors.transparent,
        child: InkWell(
          key: Key('contribution_row_${contribution.id}'),
          onTap: () => _confirmRemoval(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pending
                            ? '${contribution.amount.format()} detectada'
                            : 'Guardei',
                        style: context.texts.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _subtitle(),
                        style: context.texts.labelSmall?.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (pending)
                  AppButton(
                    key: Key('confirm_contribution_${contribution.id}'),
                    label: 'Confirmar',
                    variant: AppButtonVariant.secondary,
                    expand: false,
                    onPressed: () => ref
                        .read(savingsRepositoryProvider)
                        .confirmContribution(contribution.id),
                  )
                else
                  // Aporte confirmado é dinheiro entrando na meta: mesma cor e
                  // mesmo `+` de uma receita.
                  MoneyText.income(contribution.amount),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pergunta antes, e diz o que sai junto.
  ///
  /// A frase muda com [SavingsContribution.hasTransaction]: prometer que "o
  /// lançamento sai junto" quando não há lançamento seria mentira — e é o caso
  /// de toda linha anterior à migration 20260728000822.
  Future<void> _confirmRemoval(BuildContext context, WidgetRef ref) async {
    final amount = contribution.amount.format();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover esta contribuição?'),
        content: Text(
          contribution.hasTransaction
              ? 'A meta volta a ficar $amount atrás, e o lançamento de $amount '
                    'sai do extrato junto — é o mesmo dinheiro visto dos dois '
                    'lados. O saldo da conta não é afetado.'
              : 'A meta volta a ficar $amount atrás. Esta contribuição não tem '
                    'lançamento ligado, então o extrato não muda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_delete_contribution'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(savingsRepositoryProvider).deleteContribution(contribution);
  }

  String _subtitle() {
    final day = formatDayLabel(contribution.contributedAt.toLocal());
    final origin = contribution.source == ContributionSource.manual
        ? 'manual'
        : 'Open Finance';
    return '$day · $origin';
  }
}

/// Rodapé fixo com a única ação da tela.
class _Footer extends ConsumerWidget {
  const _Footer({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      AppSpacing.md,
      AppSpacing.screenGutter,
      AppSpacing.lg,
    ),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      border: Border(top: BorderSide(color: context.tokens.hairline)),
    ),
    child: SafeArea(
      top: false,
      child: AppButton(
        key: const Key('add_contribution'),
        label: 'Guardei um valor',
        icon: Icons.add,
        onPressed: () => ContributionSheet.show(context, goal: progress.goal),
      ),
    ),
  );
}

class _GoalGone extends StatelessWidget {
  const _GoalGone();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: const Padding(
      padding: EdgeInsets.all(AppSpacing.screenGutter),
      child: Center(
        child: AppEmptyState(
          icon: Icons.help_outline,
          title: 'Meta não encontrada',
          message: 'Ela pode ter sido excluída em outro aparelho.',
        ),
      ),
    ),
  );
}
