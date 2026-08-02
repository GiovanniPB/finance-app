import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../spaces/domain/space_member.dart';
import '../../spaces/domain/space_permissions.dart';
import '../../spaces/presentation/member_copy.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../domain/expense_split.dart';
import '../domain/transaction.dart';
import 'transaction_edit_controller.dart';
import 'transactions_providers.dart';

/// "Dividido entre": o rateio igual do lançamento, e como mexer nele.
///
/// ─────────────────────────────────────────────────────────────────────────
/// POR QUE UM BOTÃO, E NÃO UM SELETOR DE MODALIDADE
///
/// Só existe rateio igual nesta fatia. Percentual (usando o
/// `share_percentage` que `space_members` já tem) e valor exato pedem tela de
/// configuração, e uma tela dessas dentro de uma folha que já avisa no
/// cabeçalho que "seis campos e um teclado não cabem numa tela pequena" é
/// fatia inteira. Um seletor com uma opção só seria promessa de duas que não
/// existem.
///
/// A linha "Soma das partes" não é decoração: é o que torna verificável, sem
/// confiar no código, que o centavo que não divide não se perdeu.
///
/// ─────────────────────────────────────────────────────────────────────────
/// "QUEM PAGOU" VEM ANTES DE "DIVIDIDO ENTRE"
///
/// O rateio só significa alguma coisa depois de se saber quem adiantou o
/// dinheiro: "cada um deve R$ 80" não diz a quem. Na ordem inversa a pessoa
/// leria o rateio, faria a pergunta, e teria de voltar.
///
/// Diferente do botão de dividir, o pagador **não** grava ao toque: ele é campo
/// do formulário e sobe no "Salvar", junto do resto.
class SplitSection extends ConsumerStatefulWidget {
  const SplitSection({required this.transaction, super.key});

  final Transaction transaction;

  @override
  ConsumerState<SplitSection> createState() => _SplitSectionState();
}

class _SplitSectionState extends ConsumerState<SplitSection> {
  bool _isWorking = false;
  String? _errorMessage;

  Future<void> _run(Future<Result<Object?, Failure>> Function() action) async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    final result = await action();
    if (!mounted) return;

    setState(() {
      _isWorking = false;
      _errorMessage = switch (result) {
        Ok() => null,
        Err(:final failure) => failure.message,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final splits =
        ref
            .watch(transactionSplitsProvider(widget.transaction.id))
            .asData
            ?.value ??
        const <ExpenseSplit>[];
    final members =
        ref
            .watch(spaceMembersProvider(widget.transaction.spaceId))
            .asData
            ?.value ??
        const <SpaceMember>[];
    final permissions = ref.watch(
      spacePermissionsProvider(widget.transaction.spaceId),
    );
    final error = _errorMessage;
    final repository = ref.read(transactionsRepositoryProvider);

    final paidBy = ref.watch(
      transactionEditControllerProvider(
        widget.transaction,
      ).select((state) => state.paidBy),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Divider(height: 1, color: tokens.hairline),
        const SizedBox(height: AppSpacing.lg),
        Text('Quem pagou', style: context.texts.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final member in members.where((m) => m.isActive))
              CategoryChip(
                key: Key('payer_${member.userId}'),
                label: _shortLabelFor(member.userId, members, permissions),
                icon: Icons.person_outline,
                isSelected: member.userId == paidBy,
                onSelected: () => ref
                    .read(
                      transactionEditControllerProvider(
                        widget.transaction,
                      ).notifier,
                    )
                    .selectPayer(member.userId),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text('Dividido entre', style: context.texts.titleSmall),
            ),
            if (splits.isNotEmpty)
              Text(
                '${splits.length} pessoas',
                style: context.texts.labelSmall?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        if (splits.isEmpty)
          AppButton(
            key: const Key('transaction_split'),
            label: 'Dividir igualmente',
            variant: AppButtonVariant.ghost,
            isLoading: _isWorking,
            onPressed: _isWorking
                ? null
                : () => _run(
                    () => repository.splitEqually(widget.transaction.id),
                  ),
          )
        else ...[
          for (final split in splits)
            _SplitRow(
              key: Key('split_${split.userId}'),
              split: split,
              // A linha usa o nome que a fatia `nome-de-membro` trouxe, e cai
              // no mesmo texto de antes quando a pessoa ainda não definiu o
              // dela — inclusive o "· você" da própria linha.
              label: _labelFor(split, members, permissions),
            ),
          const SizedBox(height: AppSpacing.sm),
          _SplitTotal(splits: splits),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const Key('transaction_unsplit'),
            label: 'Desfazer a divisão',
            variant: AppButtonVariant.ghost,
            isLoading: _isWorking,
            onPressed: _isWorking
                ? null
                : () =>
                      _run(() => repository.removeSplit(widget.transaction.id)),
          ),
        ],

        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error,
            key: const Key('transaction_split_error'),
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.error,
            ),
          ),
        ],
      ],
    );
  }

  /// Como a pessoa da parte se chama.
  ///
  /// Reusa `MemberCopy` para as duas telas dizerem a mesma coisa da mesma
  /// pessoa. Quando a membership não está no banco local — quem saiu depois de
  /// a despesa ser dividida —, sobra o vínculo: a parte permanece, porque
  /// apagá-la reescreveria o passado.
  String _labelFor(
    ExpenseSplit split,
    List<SpaceMember> members,
    SpacePermissions? permissions,
  ) {
    final member = members.where((m) => m.userId == split.userId).firstOrNull;
    if (member == null || permissions == null) {
      return 'Quem saiu do espaço';
    }
    return MemberCopy.identity(
      member: member,
      permissions: permissions,
      today: ref.watch(clockProvider)(),
      myDisplayName: ref.watch(myDisplayNameProvider),
    ).text;
  }

  /// O nome curto, para caber numa pílula ao lado de outras duas.
  String _shortLabelFor(
    String userId,
    List<SpaceMember> members,
    SpacePermissions? permissions,
  ) {
    if (permissions == null) return 'Membro sem nome';
    return MemberCopy.shortIdentity(
      userId: userId,
      members: members,
      permissions: permissions,
    ).label;
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({required this.split, required this.label, super.key});

  final ExpenseSplit split;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          const CategorySwatch.brand(icon: Icons.person_outline),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodyMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Tom neutro (o padrão): a parte não é despesa nem receita, é quanto
          // cabe a alguém. Pintá-la de vermelho leria como dívida vencida.
          MoneyText(split.amount, withSymbol: true),
        ],
      ),
    );
  }
}

/// A soma das partes, para o rateio ser verificável sem confiar no código.
class _SplitTotal extends StatelessWidget {
  const _SplitTotal({required this.splits});

  final List<ExpenseSplit> splits;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final total = splits.total;
    if (total == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Soma das partes',
              style: context.texts.labelSmall?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ),
          Text(
            total.format(),
            key: const Key('split_total'),
            style: context.texts.labelSmall?.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}
