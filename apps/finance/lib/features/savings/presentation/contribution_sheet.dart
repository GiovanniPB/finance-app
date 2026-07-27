import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
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

  Money get _amount =>
      Money.fromMinor(_amountMinor, currency: widget.goal.currency);

  @override
  Widget build(BuildContext context) => Padding(
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
        const SizedBox(height: AppSpacing.lg),
        AmountKeypad(onDigit: _pressDigit, onBackspace: _pressBackspace),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          key: const Key('contribution_save'),
          label: 'Guardar',
          isLoading: _isSaving,
          onPressed: _amountMinor > 0 && !_isSaving ? _save : null,
        ),
      ],
    ),
  );

  void _pressDigit(int digit) => setState(() {
    _amountMinor = MinorDigits.append(_amountMinor, digit);
    _error = null;
  });

  void _pressBackspace() => setState(() {
    _amountMinor = MinorDigits.removeLast(_amountMinor);
    _error = null;
  });

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final result = await ref
        .read(savingsRepositoryProvider)
        .addContribution(goal: widget.goal, amount: _amount);

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
