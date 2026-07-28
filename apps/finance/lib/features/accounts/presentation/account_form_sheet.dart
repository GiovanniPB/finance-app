import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../spaces/domain/space.dart';
import '../domain/account.dart';
import 'account_form_controller.dart';
import 'account_icons.dart';
import 'accounts_providers.dart';

/// Cria ou edita uma conta (PRD §5.2).
///
/// Uma folha só, com dois modos, porque os campos são os mesmos: separar em
/// "nova" e "editar" duplicaria seis campos para ganhar um título diferente.
///
/// O saldo usa o mesmo teclado do registro rápido e do orçamento. Informar
/// saldo é digitar um valor, e o produto já tem um jeito de digitar valor —
/// abrir o teclado do sistema aqui seria um gesto a mais para aprender.
///
/// **Conta de Open Finance é editável só em parte**, e a divisão vem do
/// ADR 0005: tipo, moeda e saldo pertencem à Pluggy (a sincronização os
/// reescreve), então eles não aparecem como campo — aparecem como fato, com a
/// data do saldo. Nome, instituição, alvo de poupança e espaço vinculado seguem
/// do usuário, porque a ingestão nunca os toca depois do primeiro INSERT.
/// Deixar o saldo editável era oferecer um campo cujo valor desaparece na
/// próxima sincronização.
class AccountFormSheet extends ConsumerStatefulWidget {
  const AccountFormSheet({this.editing, super.key});

  /// Conta em edição. Nulo abre a folha para uma conta nova.
  final Account? editing;

  /// Abre a folha. Devolve `true` quando a conta foi salva ou removida.
  static Future<bool?> show(BuildContext context, {Account? editing}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AccountFormSheet(editing: editing),
      );

  @override
  ConsumerState<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<AccountFormSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name,
  );
  late final TextEditingController _institution = TextEditingController(
    text: widget.editing?.institution,
  );

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    super.dispose();
  }

  AccountFormController get _controller =>
      ref.read(accountFormControllerProvider(widget.editing).notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountFormControllerProvider(widget.editing));
    final linkable = ref.watch(linkableSpacesProvider);
    final imported = widget.editing?.isFromOpenFinance ?? false;

    return ConstrainedBox(
      // Seis campos e um teclado não cabem numa tela pequena: os campos rolam
      // e Salvar fica num rodapé fixo. Mesmo desenho da edição de lançamento.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.sheetPadding,
          AppSpacing.sm,
          AppSpacing.sheetPadding,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetGrabHandle(),
            Text(
              state.isEditing ? 'Editar conta' : 'Nova conta',
              textAlign: TextAlign.center,
              style: context.texts.titleMedium,
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    if (imported)
                      _ProviderOwnedSummary(account: widget.editing!)
                    else
                      _TypePicker(
                        selected: state.type,
                        onSelected: _controller.selectType,
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      label: 'Nome',
                      hint: 'Ex.: Conta corrente',
                      controller: _name,
                      onChanged: _controller.editName,
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        state.errorMessage!,
                        key: const Key('account_form_error'),
                        textAlign: TextAlign.center,
                        style: context.texts.bodySmall?.copyWith(
                          color: context.colors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      label: 'Instituição',
                      hint: 'Opcional',
                      controller: _institution,
                      onChanged: _controller.editInstitution,
                    ),
                    // Saldo e teclado só na conta manual: numa importada o
                    // número é da Pluggy e aparece em `_ProviderOwnedSummary`.
                    if (!imported) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _BalanceField(state: state),
                      const SizedBox(height: AppSpacing.lg),
                      AmountKeypad(
                        onDigit: _controller.pressDigit,
                        onBackspace: _controller.pressBackspace,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    _SavingsTargetToggle(
                      value: state.isSavingsTarget,
                      onChanged: _controller.toggleSavingsTarget,
                    ),
                    if (linkable.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _LinkedSpaceField(
                        spaces: linkable,
                        selectedId: state.linkedSpaceId,
                        onSelected: _controller.selectLinkedSpace,
                      ),
                    ],
                    // Respiro no fim da rolagem: sem isto o último campo
                    // encosta no rodapé fixo e fica difícil de tocar.
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: state.isEditing ? 'Salvar' : 'Criar conta',
              isLoading: state.isSaving,
              onPressed: state.canSave ? _save : null,
            ),
            // Excluir não existe em conta importada, e não é zelo excessivo: a
            // sincronização a **recria** (o worker insere quando não encontra o
            // `external_id`), com nome padrão, sem o alvo de poupança nem o
            // espaço vinculado. E como a dedup de lançamento é por
            // `account_id`, a conta nova reimportaria o extrato inteiro
            // enquanto o antigo ficaria órfão — a FK põe `account_id` em nulo.
            // Um toque viraria histórico duplicado. Quem termina o vínculo é
            // "Remover banco", no Perfil.
            if (state.isEditing && !imported) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const Key('account_delete'),
                label: 'Excluir conta',
                variant: AppButtonVariant.ghost,
                onPressed: state.isSaving ? null : _confirmDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final saved = await _controller.save();
    if (saved != null && mounted) Navigator.of(context).pop(true);
  }

  /// Excluir é irreversível e o alvo é dado financeiro: confirma, e diz o que
  /// acontece com os lançamentos (a FK é `on delete set null` — eles ficam).
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir conta?'),
        content: const Text(
          'Os lançamentos ligados a ela continuam existindo, mas ficam sem '
          'conta. Isso não pode ser desfeito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_delete_account'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final removed = await _controller.remove();
    if (removed && mounted) Navigator.of(context).pop(true);
  }
}

/// O que a Pluggy é dona, numa conta importada: tipo e saldo, como fato.
///
/// **Não é um campo desabilitado.** Campo cinza convida a tocar e não responde;
/// isto é uma afirmação, com a data do saldo e a frase que explica por que não
/// há o que editar. O mesmo desenho que a folha de lançamento usa quando
/// detecta que o lançamento pertence a uma meta: ela vira leitura e aponta para
/// onde a coisa se resolve.
class _ProviderOwnedSummary extends StatelessWidget {
  const _ProviderOwnedSummary({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Minúscula porque a data entra no meio da frase: `formatDayLabel` devolve
    // "Hoje", e "de Hoje" lê como erro de digitação.
    final asOf = formatDayLabel(account.balanceAsOf.toLocal()).toLowerCase();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppRadii.brMd,
        border: Border.all(color: tokens.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    account.type.label,
                    style: context.texts.labelMedium,
                  ),
                ),
                MoneyText(account.signedBalance, size: MoneySize.small),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Tipo e saldo vêm do banco — saldo de $asOf. Editar aqui seria '
              'desfeito na próxima sincronização.',
              key: const Key('account_provider_owned'),
              style: context.texts.bodySmall?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tipo da conta, em chips.
///
/// Seis opções não cabem num segmento e não merecem um menu: chip mostra todas
/// de uma vez, e o tipo muda o significado do saldo logo abaixo — esconder a
/// escolha atrás de um toque tornaria essa relação invisível.
class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.selected, required this.onSelected});

  final AccountType selected;
  final ValueChanged<AccountType> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Tipo', style: context.texts.labelMedium),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final type in AccountType.values)
            _TypeChip(
              key: Key('account_type_${type.db}'),
              type: type,
              isSelected: type == selected,
              onTap: () => onSelected(type),
            ),
        ],
      ),
    ],
  );
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final AccountType type;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: isSelected ? tokens.brandSubtle : tokens.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.brMd,
        side: BorderSide(
          color: isSelected ? context.colors.primary : tokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.brMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                accountTypeIcon(type),
                size: 16,
                color: isSelected ? tokens.brandText : tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                type.label,
                style: context.texts.labelMedium?.copyWith(
                  color: isSelected ? tokens.brandText : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saldo mais a legenda que diz o que aquele número significa.
///
/// Em cartão de crédito o número é a fatura — dívida — e não saldo disponível.
/// A legenda troca junto com o tipo em vez de o app inventar um sinal negativo
/// que o usuário não digitou.
class _BalanceField extends StatelessWidget {
  const _BalanceField({required this.state});

  final AccountFormState state;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AmountDisplay(label: state.balanceLabel),
      const SizedBox(height: AppSpacing.xs),
      Text(
        state.balanceHint,
        key: const Key('account_balance_hint'),
        textAlign: TextAlign.center,
        style: context.texts.bodySmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
    ],
  );
}

/// Marca a conta como destino de poupança (usado pelas metas, na Fase 1).
class _SavingsTargetToggle extends StatelessWidget {
  const _SavingsTargetToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.sm,
      AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: context.tokens.surfaceSunken,
      borderRadius: AppRadii.brMd,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Guardo dinheiro aqui', style: context.texts.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'As metas de poupança vão olhar para esta conta.',
                style: context.texts.bodySmall?.copyWith(
                  color: context.tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          key: const Key('account_savings_target'),
          value: value,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

/// Vínculo da conta a um household (ADR 0004).
///
/// Só aparece quando existe household — ver `linkableSpacesProvider`. Vincular
/// deixa a conta visível para os outros membros; editar continua sendo só do
/// dono, e é o RLS quem garante isso.
class _LinkedSpaceField extends StatelessWidget {
  const _LinkedSpaceField({
    required this.spaces,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Space> spaces;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Visível para', style: context.texts.labelMedium),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          _LinkChip(
            label: 'Só eu',
            isSelected: selectedId == null,
            onTap: () => onSelected(null),
          ),
          for (final space in spaces)
            _LinkChip(
              key: Key('link_space_${space.id}'),
              label: space.name,
              isSelected: space.id == selectedId,
              onTap: () => onSelected(space.id),
            ),
        ],
      ),
    ],
  );
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: isSelected ? tokens.brandSubtle : tokens.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.brFull,
        side: BorderSide(
          color: isSelected ? context.colors.primary : tokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.brFull,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: context.texts.labelMedium?.copyWith(
              color: isSelected ? tokens.brandText : null,
            ),
          ),
        ),
      ),
    );
  }
}
