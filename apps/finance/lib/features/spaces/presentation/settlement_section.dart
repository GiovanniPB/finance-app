import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../../transactions/domain/settlement.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/space.dart';
import '../domain/space_member.dart';
import '../domain/space_permissions.dart';
import 'member_copy.dart';
import 'spaces_providers.dart';

/// "Acertar contas": quem deve a quem, e o registro de que a dívida foi paga.
///
/// ─────────────────────────────────────────────────────────────────────────
/// TRÊS VAZIOS, TRÊS FRASES
///
/// Nada dividido, tudo quite e moeda divergente chegam aqui com a mesma lista
/// vazia, e dizer "nada aqui" nos três faria a pessoa concluir que a divisão
/// não funcionou. O primeiro ensina **onde** dividir (a marcação mora na folha
/// de edição, não no `+`); o segundo é resultado; o terceiro recusa somar.
///
/// ─────────────────────────────────────────────────────────────────────────
/// QUEM OLHA SE ACHA PELO PESO, NÃO POR FUNDO COLORIDO
///
/// Em grupo de três quase toda transferência envolve você, e destacar todas
/// seria destacar nenhuma. O que muda é a palavra "Você", em peso e cor de
/// marca. A linha que **não** envolve você aparece igual, sem apagar: esconder
/// metade faria as transferências não somarem com o saldo, e alguém pagaria
/// duas vezes.
class SettlementSection extends ConsumerWidget {
  const SettlementSection({required this.space, super.key});

  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlement = ref.watch(settlementProvider(space.id)).asData?.value;
    if (settlement == null) return const SizedBox.shrink();

    final members =
        ref.watch(spaceMembersProvider(space.id)).asData?.value ??
        const <SpaceMember>[];
    final permissions = ref.watch(spacePermissionsProvider(space.id));
    final myUserId = permissions?.myUserId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Acertar contas', style: context.texts.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (settlement.isMixedCurrency)
          const _Empty(
            key: Key('settlement_mixed_currency'),
            headline: 'Há mais de uma moeda neste grupo.',
            hint:
                'O saldo não soma valores em moedas diferentes — somar daria '
                'um número errado com cara de certo.',
          )
        else if (settlement.hasNothingSplit)
          const _Empty(
            key: Key('settlement_nothing_split'),
            headline: 'Nenhuma despesa dividida.',
            hint:
                'Abra uma despesa do grupo e toque em “Dividir igualmente” — '
                'o saldo aparece aqui.',
          )
        else if (settlement.isAllSettled)
          _Empty(
            key: const Key('settlement_all_settled'),
            headline: 'Está tudo quite.',
            hint:
                'As ${settlement.splitCount} despesas divididas do grupo já se '
                'cancelam — ninguém deve nada a ninguém.',
          )
        else ...[
          _MyPosition(
            settlement: settlement,
            myUserId: myUserId,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final transfer in settlement.transfers)
            _TransferRow(
              key: Key(
                'transfer_${transfer.fromUserId}_${transfer.toUserId}',
              ),
              transfer: transfer,
              space: space,
              members: members,
              permissions: permissions,
              myUserId: myUserId,
            ),
          const SizedBox(height: AppSpacing.sm),
          _Footer(settlement: settlement),
        ],
      ],
    );
  }
}

/// A primeira pergunta de quem abre a tela é "e eu?".
class _MyPosition extends StatelessWidget {
  const _MyPosition({required this.settlement, required this.myUserId});

  final Settlement settlement;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final net = myUserId == null ? null : settlement.balanceOf(myUserId!)?.net;

    // Sem saldo próprio (quem entrou depois de tudo, ou sessão ainda
    // sincronizando) a faixa some em vez de mostrar R$ 0,00 — zero aqui leria
    // como "quite", que é outra coisa.
    if (net == null || net.isZero) return const SizedBox.shrink();

    final isCredit = net.isPositive;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 3,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: AppRadii.brMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isCredit ? 'Você tem a receber' : 'Você deve',
              style: context.texts.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ),
          // Ter a receber usa a cor da marca com `+` explícito, como receita;
          // dever fica **neutro**. Vermelho neste sistema é orçamento estourado
          // e erro real, e dever ao colega de casa não é erro — ver a regra
          // central em `app_tokens.dart`.
          MoneyText(
            key: const Key('settlement_my_position'),
            net.abs,
            tone: isCredit ? MoneyTone.positive : MoneyTone.neutral,
            size: MoneySize.large,
            withSymbol: true,
          ),
        ],
      ),
    );
  }
}

/// Uma transferência proposta. Tocável só quando envolve quem está olhando.
class _TransferRow extends ConsumerStatefulWidget {
  const _TransferRow({
    required this.transfer,
    required this.space,
    required this.members,
    required this.permissions,
    required this.myUserId,
    super.key,
  });

  final SettlementTransfer transfer;
  final Space space;
  final List<SpaceMember> members;
  final SpacePermissions? permissions;
  final String? myUserId;

  @override
  ConsumerState<_TransferRow> createState() => _TransferRowState();
}

class _TransferRowState extends ConsumerState<_TransferRow> {
  bool _isWorking = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final transfer = widget.transfer;
    final myUserId = widget.myUserId;
    final isMine = myUserId != null && transfer.involves(myUserId);

    final from = _identityOf(transfer.fromUserId);
    final to = _identityOf(transfer.toUserId);
    final error = _errorMessage;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              // A seta é decorativa: sem esta frase o leitor de tela anuncia
              // "Carla seta Você", que não é o que a linha diz.
              label:
                  '${from.text} paga ${transfer.amount.format()} '
                  'a ${to.text}',
              excludeSemantics: true,
              child: Row(
                children: [
                  Flexible(
                    child: _Party(
                      identity: from,
                      isMe: transfer.fromUserId == myUserId,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ),
                  Flexible(
                    child: _Party(
                      identity: to,
                      isMe: transfer.toUserId == myUserId,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          MoneyText(transfer.amount, withSymbol: true),
          SizedBox(
            width: 20,
            child: isMine
                ? Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: tokens.textMuted,
                  )
                : null,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isMine && !_isWorking)
          InkWell(onTap: () => _confirm(from, to), child: row)
        else
          row,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              error,
              key: const Key('settlement_error'),
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        Divider(height: 1, color: tokens.hairline),
      ],
    );
  }

  MemberIdentity _identityOf(String userId) {
    final permissions = widget.permissions;
    if (permissions == null) {
      return (label: 'Membro sem nome', qualifier: null);
    }
    return MemberCopy.shortIdentity(
      userId: userId,
      members: widget.members,
      permissions: permissions,
    );
  }

  /// Confirma antes de gravar: o acerto cria um lançamento no grupo, e ninguém
  /// espera que "já paguei" apareça na lista do mês sem aviso.
  Future<void> _confirm(MemberIdentity from, MemberIdentity to) async {
    final transfer = widget.transfer;
    final iPaid = transfer.fromUserId == widget.myUserId;
    final other = iPaid ? to.label : from.label;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          iPaid ? 'Você já pagou $other?' : '$other te pagou?',
        ),
        content: Text(
          'Registra uma transferência de ${transfer.amount.format()} '
          '${iPaid ? 'de você para $other' : 'de $other para você'} '
          'no grupo ${widget.space.name}. O saldo entre vocês vai a zero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_settle'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    final result = await ref
        .read(settlementRepositoryProvider)
        .settle(
          spaceId: widget.space.id,
          fromUserId: transfer.fromUserId,
          toUserId: transfer.toUserId,
          amount: transfer.amount,
          description: 'Acerto com ${iPaid ? other : from.label}',
        );

    if (!mounted) return;
    setState(() {
      _isWorking = false;
      _errorMessage = switch (result) {
        Ok() => null,
        Err(:final failure) => failure.message,
      };
    });
  }
}

/// Uma ponta da transferência. "Você" lidera em peso e cor de marca.
class _Party extends StatelessWidget {
  const _Party({required this.identity, required this.isMe});

  final MemberIdentity identity;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final qualifier = identity.qualifier;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: identity.label,
            style: isMe
                ? context.texts.bodyMedium?.copyWith(
                    color: tokens.brandText,
                    fontWeight: FontWeight.w600,
                  )
                : context.texts.bodyMedium,
          ),
          if (qualifier != null)
            TextSpan(
              text: ' · $qualifier',
              style: context.texts.bodySmall?.copyWith(
                color: tokens.textMuted,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// O que a lista de transferências é, em números, mais como agir sobre ela.
class _Footer extends StatelessWidget {
  const _Footer({required this.settlement});

  final Settlement settlement;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = context.texts.labelSmall?.copyWith(color: tokens.textMuted);
    final count = settlement.transfers.length;
    final splits = settlement.splitCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                count == 1
                    ? '1 transferência zera o grupo'
                    : '$count transferências zeram o grupo',
                style: style,
              ),
            ),
            Text(
              splits == 1 ? '1 despesa dividida' : '$splits despesas divididas',
              style: style,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Toque na sua linha para registrar o acerto.',
          key: const Key('settlement_hint'),
          style: style,
        ),
      ],
    );
  }
}

/// Um dos três vazios. Sempre com a frase que diz o que aquele vazio significa.
class _Empty extends StatelessWidget {
  const _Empty({required this.headline, required this.hint, super.key});

  final String headline;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(headline, style: context.texts.bodyMedium),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        hint,
        style: context.texts.bodySmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
    ],
  );
}
