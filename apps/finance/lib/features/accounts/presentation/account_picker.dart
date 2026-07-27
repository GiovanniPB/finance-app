import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/account.dart';
import 'account_icons.dart';

/// Chips de conta em rolagem horizontal, para dizer de onde saiu o dinheiro.
///
/// Mesmo gesto do `CategoryPicker`: escolher conta e escolher categoria são a
/// mesma operação mental, e devem parecer a mesma.
///
/// **Não aparece quando não há conta.** Quem nunca cadastrou uma não deve
/// esbarrar num campo vazio no caminho de 30 segundos do registro rápido — e
/// quem tem exatamente uma também não precisa tocar em nada (ver
/// `QuickEntryController.build`, que já a seleciona).
///
/// O rótulo existe porque logo acima há outra fila de chips: duas filas
/// idênticas sem rótulo viram adivinhação.
class AccountPicker extends StatelessWidget {
  const AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.onSelected,
    this.label = 'Conta',
    super.key,
  });

  final List<Account> accounts;
  final String? selectedId;

  /// Recebe `null` quando a conta selecionada é tocada de novo — lançamento
  /// sem conta é estado válido (é o de todo lançamento até esta fatia).
  final ValueChanged<String?> onSelected;

  final String label;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.texts.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: accounts.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final account = accounts[index];
              final isSelected = account.id == selectedId;

              return CategoryChip(
                key: Key('account_chip_${account.id}'),
                label: account.name,
                icon: accountTypeIcon(account.type),
                isSelected: isSelected,
                onSelected: () => onSelected(isSelected ? null : account.id),
              );
            },
          ),
        ),
      ],
    );
  }
}
