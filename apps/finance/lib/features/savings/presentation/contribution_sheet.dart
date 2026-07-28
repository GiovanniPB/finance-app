import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/presentation/account_picker.dart';
import '../../accounts/presentation/accounts_providers.dart';
import '../domain/savings_goal.dart';

/// "Guardei um valor" — o caminho manual da RN-3.2.
///
/// É o único caminho que existe nesta fatia: a detecção automática depende da
/// ingestão do Open Finance (ADR 0005), que ainda não existe. O schema já
/// distingue as duas origens, então quando a ingestão chegar ela só grava com
/// `detected_via = open_finance` e esta folha continua igual.
///
/// Mesmo gesto do registro rápido — valor no teclado próprio, uma ação — porque
/// guardar dinheiro é a mesma operação mental de registrar gasto com o sinal
/// invertido. Reaproveitar o gesto é o que faz o app parecer um só.
///
/// A folha pergunta **de que conta o dinheiro saiu**, e não para onde foi: o
/// destino já é a meta (e a conta dela, quando há `linkedAccountId`). Guardar
/// valor grava um lançamento `savings` junto com a contribuição, e é esse
/// lançamento que precisa da conta de origem.
class ContributionSheet extends ConsumerStatefulWidget {
  const ContributionSheet({required this.goal, super.key});

  final SavingsGoal goal;

  /// Abre a folha. Devolve `true` quando o valor foi registrado.
  static Future<bool?> show(
    BuildContext context, {
    required SavingsGoal goal,
  }) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ContributionSheet(goal: goal),
  );

  @override
  ConsumerState<ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends ConsumerState<ContributionSheet> {
  int _amountMinor = 0;
  bool _isSaving = false;
  String? _error;
  String? _accountId;

  /// Distingue "ainda não escolhi" de "tirei de propósito".
  ///
  /// Sem essa marca, desmarcar a conta única seria desfeito pelo padrão na hora
  /// de salvar — o mesmo raciocínio de `QuickEntryState.accountTouched`.
  bool _accountTouched = false;

  Money get _amount =>
      Money.fromMinor(_amountMinor, currency: widget.goal.currency);

  /// A conta que o Salvar vai gravar: a escolhida, ou a única que existe.
  String? _effectiveAccountId(String? soleAccountId) =>
      _accountTouched ? _accountId : soleAccountId;

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(spaceAccountsProvider).asData?.value ?? const <Account>[];
    final soleAccountId = ref.watch(soleAccountIdProvider);

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
          Text('Guardei um valor', style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Em ${widget.goal.name}',
            style: context.texts.bodySmall?.copyWith(
              color: context.tokens.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AmountDisplay(label: _amount.format(withSymbol: false)),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              key: const Key('contribution_error'),
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
          // Sem conta cadastrada o campo não aparece: o lançamento fica sem
          // conta, como qualquer outro. Perguntar sobre um conjunto vazio é
          // pedir para o usuário resolver um problema que não é dele.
          if (accounts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AccountPicker(
              label: 'Saiu de',
              accounts: accounts,
              selectedId: _effectiveAccountId(soleAccountId),
              onSelected: (accountId) => setState(() {
                _accountId = accountId;
                _accountTouched = true;
              }),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AmountKeypad(onDigit: _pressDigit, onBackspace: _pressBackspace),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const Key('contribution_save'),
            label: 'Guardar',
            isLoading: _isSaving,
            onPressed: _amountMinor > 0 && !_isSaving
                ? () => _save(soleAccountId)
                : null,
          ),
        ],
      ),
    );
  }

  void _pressDigit(int digit) => setState(() {
    _amountMinor = MinorDigits.append(_amountMinor, digit);
    _error = null;
  });

  void _pressBackspace() => setState(() {
    _amountMinor = MinorDigits.removeLast(_amountMinor);
    _error = null;
  });

  Future<void> _save(String? soleAccountId) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final result = await ref
        .read(savingsRepositoryProvider)
        .addContribution(
          goal: widget.goal,
          amount: _amount,
          accountId: _effectiveAccountId(soleAccountId),
        );

    if (!mounted) return;

    switch (result) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() {
          _isSaving = false;
          _error = failure.message;
        });
    }
  }
}
