import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/domain/account.dart';
import '../../accounts/presentation/accounts_providers.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/savings_goal.dart';
import 'goal_form_controller.dart';
import 'goal_icons.dart';

/// Cria ou edita uma meta de poupança, em dois passos.
///
/// **Passo 1 escolhe o tipo; passo 2 mostra só os campos daquele tipo.** Não é
/// preciosismo de fluxo: os três tipos juntos somam nome, valor, percentual,
/// prazo e conta, e essa união mais o teclado numérico não cabe numa folha — é
/// o defeito já catalogado na folha de editar conta, onde a última fileira do
/// teclado fica cortada. Separar também deixa cada passo com uma pergunta só.
///
/// Editar entra direto no passo 2: o tipo é identidade da meta e não muda.
class GoalFormSheet extends ConsumerWidget {
  const GoalFormSheet({this.editing, super.key});

  /// Meta em edição. Nula abre a folha para uma meta nova.
  final SavingsGoal? editing;

  /// Abre a folha. Devolve `true` quando a meta foi salva ou removida.
  static Future<bool?> show(BuildContext context, {SavingsGoal? editing}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => GoalFormSheet(editing: editing),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = goalFormControllerProvider(editing);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sheetPadding,
        AppSpacing.sm,
        AppSpacing.sheetPadding,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetGrabHandle(),
          _Head(state: state, onBack: controller.backToType),
          const SizedBox(height: AppSpacing.lg),
          // Campos rolando, ações em rodapé fixo — a mesma divisão da folha de
          // edição de lançamento. Sem a rolagem, uma tela baixa corta a última
          // fileira do teclado, e alvo de toque cortado lê como defeito (é o
          // débito conhecido da folha de editar conta).
          Flexible(
            child: SingleChildScrollView(
              child: state.step == GoalFormStep.type
                  ? _TypeStep(state: state, controller: controller)
                  : _DetailsStep(state: state, controller: controller),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Actions(state: state, controller: controller),
        ],
      ),
    );
  }
}

/// Ações da folha, fora da área de rolagem.
class _Actions extends StatelessWidget {
  const _Actions({required this.state, required this.controller});

  final GoalFormState state;
  final GoalFormController controller;

  @override
  Widget build(BuildContext context) {
    if (state.step == GoalFormStep.type) {
      return AppButton(
        key: const Key('goal_form_continue'),
        label: 'Continuar',
        onPressed: controller.goToDetails,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: const Key('goal_form_save'),
          label: state.isEditing ? 'Salvar meta' : 'Criar meta',
          isLoading: state.isSaving,
          onPressed: () async {
            final saved = await controller.save();
            if (saved && context.mounted) Navigator.of(context).pop(true);
          },
        ),
        if (state.isEditing) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const Key('goal_form_remove'),
            label: 'Excluir meta',
            variant: AppButtonVariant.ghost,
            onPressed: state.isSaving
                ? null
                : () async {
                    final confirmed = await _confirmRemoval(context);
                    if (!confirmed) return;
                    final removed = await controller.remove();
                    if (removed && context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
          ),
        ],
      ],
    );
  }

  /// Excluir meta apaga o histórico de contribuições dela — pergunta antes.
  Future<bool> _confirmRemoval(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir esta meta?'),
        content: const Text(
          'O histórico de contribuições dela é apagado junto. O dinheiro na '
          'conta não é afetado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('goal_remove_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

/// Título, mais o tipo escolhido e a volta para trocá-lo.
class _Head extends StatelessWidget {
  const _Head({required this.state, required this.onBack});

  final GoalFormState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final title = state.isEditing ? 'Editar meta' : 'Nova meta';
    final showBack = state.step == GoalFormStep.details && !state.isEditing;

    return Row(
      children: [
        if (showBack)
          IconButton(
            key: const Key('goal_form_back'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Trocar o tipo',
            onPressed: onBack,
          ),
        Expanded(child: Text(title, style: context.texts.titleMedium)),
        if (state.step == GoalFormStep.details)
          _KindChip(type: state.type, onTap: showBack ? onBack : null),
      ],
    );
  }
}

/// O tipo escolhido, como pílula discreta. Toca para voltar e trocar.
class _KindChip extends StatelessWidget {
  const _KindChip({required this.type, this.onTap});

  final SavingsGoalType type;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: tokens.brandSubtle,
      borderRadius: AppRadii.brFull,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.brFull,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.brandBorder),
            borderRadius: AppRadii.brFull,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(GoalIcons.forType(type), size: 14, color: tokens.brandText),
              const SizedBox(width: AppSpacing.xs),
              Text(
                type.label,
                style: context.texts.labelMedium?.copyWith(
                  color: tokens.brandText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Passo 1: os três tipos, em linhas.
///
/// Linhas e não chips: cada tipo precisa de uma frase explicando o que é, e um
/// chip não carrega uma linha de texto. "Por objetivo" já vem marcado — é o
/// caso dominante, e uma tela de escolha sem nada marcado cobra um toque a mais
/// do caminho comum.
class _TypeStep extends StatelessWidget {
  const _TypeStep({required this.state, required this.controller});

  final GoalFormState state;
  final GoalFormController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'QUE TIPO DE META?',
        style: context.texts.labelSmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final type in SavingsGoalType.values) ...[
        _TypeRow(
          type: type,
          isSelected: state.type == type,
          onTap: () => controller.selectType(type),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  final SavingsGoalType type;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: isSelected ? tokens.brandSubtle : context.colors.surface,
      borderRadius: AppRadii.brLg,
      child: InkWell(
        key: Key('goal_type_${type.db}'),
        onTap: onTap,
        borderRadius: AppRadii.brLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadii.brLg,
            border: Border.all(
              color: isSelected ? tokens.brandBorder : tokens.hairline,
            ),
          ),
          child: Row(
            children: [
              // Na linha marcada o swatch é a marca SÓLIDA, não `brandSubtle`:
              // o fundo da linha já é `brandSubtle`, e um swatch da mesma cor
              // simplesmente desaparece — o ícone fica solto no ar, como se o
              // desenho tivesse esquecido dele.
              _TypeSwatch(type: type, isSelected: isSelected),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label, style: context.texts.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      type.description,
                      style: context.texts.bodySmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // O check é redundante com a borda e o preenchimento — de
              // propósito: seleção nunca depende de cor sozinha.
              if (isSelected) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.check_circle, size: 20, color: tokens.brandText),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Swatch do tipo, que inverte na linha marcada.
class _TypeSwatch extends StatelessWidget {
  const _TypeSwatch({required this.type, required this.isSelected});

  final SavingsGoalType type;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    if (!isSelected) {
      return CategorySwatch.brand(icon: GoalIcons.forType(type));
    }

    return Container(
      height: AppSizes.categorySwatch,
      width: AppSizes.categorySwatch,
      decoration: BoxDecoration(
        color: context.colors.primary,
        borderRadius: AppRadii.brMd,
      ),
      child: Center(
        child: Icon(
          GoalIcons.forType(type),
          size: AppSizes.categorySwatch * 0.5,
          color: context.colors.onPrimary,
        ),
      ),
    );
  }
}

/// Passo 2: só os campos do tipo escolhido.
class _DetailsStep extends ConsumerWidget {
  const _DetailsStep({required this.state, required this.controller});

  final GoalFormState state;
  final GoalFormController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppTextField(
        key: const Key('goal_name'),
        hint: state.suggestedName ?? 'Nome da meta',
        onChanged: controller.setName,
      ),
      const SizedBox(height: AppSpacing.lg),
      if (state.needsAmount)
        _AmountField(state: state, controller: controller)
      else
        _PercentageField(state: state, controller: controller),
      if (state.errorMessage != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          state.errorMessage!,
          key: const Key('goal_form_error'),
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(color: context.colors.error),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      _Chips(state: state, controller: controller),
      if (state.needsAmount) ...[
        const SizedBox(height: AppSpacing.lg),
        AmountKeypad(
          onDigit: controller.pressDigit,
          onBackspace: controller.pressBackspace,
        ),
      ],
    ],
  );
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.state, required this.controller});

  final GoalFormState state;
  final GoalFormController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        state.type == SavingsGoalType.objective
            ? 'VALOR-ALVO'
            : 'VALOR POR MÊS',
        style: context.texts.labelSmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      AmountDisplay(label: state.amountLabel),
    ],
  );
}

/// Percentual por presets, não por teclado.
///
/// Percentual de renda é grosso: 5 em 5 cobre a faixa real, e um preset é um
/// toque onde o teclado seriam dois. O valor escolhido aparece grande em cima,
/// como o dinheiro apareceria — o campo é o mesmo tipo de decisão.
class _PercentageField extends StatelessWidget {
  const _PercentageField({required this.state, required this.controller});

  final GoalFormState state;
  final GoalFormController controller;

  /// Cinco opções. Um sexto chip quebra para uma segunda fileira em telas de
  /// 390px, e fileira quebrada de pílulas lê como defeito de layout.
  static const _presets = [10, 15, 20, 25, 30];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'QUANTO DA RENDA',
        style: context.texts.labelSmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Center(
        child: Text(
          '${state.percentage}%',
          style: AppTypography.balance,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final preset in _presets)
            _PresetChip(
              value: preset,
              isSelected: state.percentage == preset,
              onTap: () => controller.setPercentage(preset),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _DerivedIncomeNote(percentage: state.percentage),
    ],
  );
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final int value;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: isSelected ? tokens.brandSubtle : context.colors.surface,
      borderRadius: AppRadii.brFull,
      child: InkWell(
        key: Key('goal_percentage_$value'),
        onTap: onTap,
        borderRadius: AppRadii.brFull,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadii.brFull,
            border: Border.all(
              color: isSelected ? tokens.brandBorder : tokens.hairlineStrong,
            ),
          ),
          child: Text(
            '$value%',
            style: context.texts.bodySmall?.copyWith(
              color: isSelected ? tokens.brandText : null,
              fontWeight: isSelected ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// De onde sai a renda da meta percentual.
///
/// Responde a questão aberta #1 do PRD dizendo a resposta na própria tela: a
/// base é a soma dos lançamentos de receita do mês, e não um número declarado à
/// parte que envelheceria calado. O custo é que sem receita lançada não há base
/// — e aí a nota diz isso em vez de mostrar um alvo de zero.
class _DerivedIncomeNote extends ConsumerWidget {
  const _DerivedIncomeNote({required this.percentage});

  /// Recebido por parâmetro, e não lido do controller: a família do provider é
  /// indexada pela meta em edição, e ler `(null)` daqui pegaria o estado do
  /// formulário errado quando a folha estivesse editando.
  final int percentage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final month = ref.watch(focusedMonthProvider);
    final income = ref.watch(monthSummaryProvider).income;
    final hasIncome = income.isPositive;

    // Mesma truncagem de `GoalProgress`: o alvo mostrado aqui tem de ser
    // exatamente o alvo que a meta vai cobrar depois.
    final share = Money.fromMinor((income.amountMinor * percentage) ~/ 100);

    final text = hasIncome
        ? 'A base é o que você lançar como receita no mês. Em '
              '${monthLabel(month)} foram ${income.format()}, então a meta '
              'deste mês é ${share.format()}.'
        : 'Nenhuma receita lançada em ${monthLabel(month)}, então ainda não há '
              'base para calcular $percentage%. Lance seu salário e a meta do '
              'mês aparece sozinha.';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: AppRadii.brMd,
        border: Border(
          left: BorderSide(
            width: 3,
            // Sem receita não é erro: o contorno fica neutro, nunca âmbar.
            color: hasIncome ? context.colors.primary : tokens.hairlineStrong,
          ),
        ),
      ),
      child: Text(
        text,
        key: const Key('goal_income_note'),
        style: context.texts.bodySmall?.copyWith(color: tokens.textMuted),
      ),
    );
  }
}

/// Prazo e conta, como chips.
class _Chips extends ConsumerWidget {
  const _Chips({required this.state, required this.controller});

  final GoalFormState state;
  final GoalFormController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(accountsProvider).asData?.value ?? const <Account>[];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (state.acceptsDeadline)
          _ChoiceChip(
            keyValue: 'goal_deadline',
            icon: Icons.calendar_today_outlined,
            label: state.targetDate == null
                ? 'Sem prazo'
                : _capitalize(monthLabel(state.targetDate!)),
            isSelected: state.targetDate != null,
            onTap: () async {
              final picked = await _pickDeadline(context, state.targetDate);
              if (picked != null) controller.setTargetDate(picked);
            },
            onClear: state.targetDate == null
                ? null
                : () => controller.setTargetDate(null),
          ),
        for (final account in accounts)
          _ChoiceChip(
            keyValue: 'goal_account_${account.id}',
            icon: Icons.account_balance_outlined,
            label: account.name,
            isSelected: state.linkedAccountId == account.id,
            onTap: () => controller.selectAccount(account.id),
          ),
      ],
    );
  }

  Future<DateTime?> _pickDeadline(
    BuildContext context,
    DateTime? current,
  ) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year, now.month + 6),
      // Prazo no passado não é oferecido: uma meta nova com prazo vencido
      // nasceria atrasada sem que ninguém tenha errado nada.
      firstDate: DateTime(now.year, now.month),
      lastDate: DateTime(now.year + 20),
      helpText: 'Prazo da meta',
    );
  }

  static String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.keyValue,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onClear,
  });

  final String keyValue;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: isSelected ? tokens.brandSubtle : context.colors.surface,
      borderRadius: AppRadii.brFull,
      child: InkWell(
        key: Key(keyValue),
        onTap: onTap,
        onLongPress: onClear,
        borderRadius: AppRadii.brFull,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadii.brFull,
            border: Border.all(
              color: isSelected ? tokens.brandBorder : tokens.hairlineStrong,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? tokens.brandText : tokens.textMuted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: context.texts.bodySmall?.copyWith(
                  color: isSelected ? tokens.brandText : null,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
