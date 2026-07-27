import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/domain/category.dart';
import '../../categories/presentation/categories_providers.dart';
import '../../categories/presentation/category_picker.dart';
import '../domain/transaction.dart';
import 'transaction_edit_controller.dart';
import 'transaction_list.dart' show formatDayLabel;

/// Detalhe e edição de um lançamento (PRD §11.2).
///
/// É uma folha, e não uma página de leitura com um botão "editar": o lançamento
/// tem seis campos e nenhum deles precisa de contexto extra para ser entendido.
/// Abrir já editável poupa um toque no caso comum — corrigir valor ou categoria
/// de algo registrado às pressas.
class TransactionEditSheet extends ConsumerStatefulWidget {
  const TransactionEditSheet({required this.transaction, super.key});

  final Transaction transaction;

  /// Abre a folha. Devolve `true` quando o lançamento foi salvo ou excluído.
  static Future<bool?> show(
    BuildContext context,
    Transaction transaction,
  ) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TransactionEditSheet(transaction: transaction),
  );

  @override
  ConsumerState<TransactionEditSheet> createState() =>
      _TransactionEditSheetState();
}

class _TransactionEditSheetState extends ConsumerState<TransactionEditSheet> {
  late final TextEditingController _description = TextEditingController(
    text: widget.transaction.description,
  );

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  TransactionEditController get _controller =>
      ref.read(transactionEditControllerProvider(widget.transaction).notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      transactionEditControllerProvider(widget.transaction),
    );
    final categories =
        ref.watch(categoriesProvider).asData?.value ?? const <Category>[];

    return ConstrainedBox(
      // Seis campos e um teclado não cabem numa tela pequena. A folha cresce
      // até quase a tela inteira, os campos rolam, e Salvar/Excluir ficam num
      // rodapé fixo: ação primária fora de vista é defeito, não densidade.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Padding(
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
            _Header(transaction: widget.transaction),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    if (state.canSwitchType)
                      AppSegmentedControl(
                        segments: const ['Despesa', 'Receita'],
                        selectedIndex: state.type == TransactionType.income
                            ? 1
                            : 0,
                        onChanged: (index) => _controller.selectType(
                          index == 1
                              ? TransactionType.income
                              : TransactionType.expense,
                        ),
                      )
                    else
                      _FixedType(type: state.type),
                    const SizedBox(height: AppSpacing.lg),
                    AmountDisplay(label: state.amountLabel),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        state.errorMessage!,
                        key: const Key('transaction_edit_error'),
                        textAlign: TextAlign.center,
                        style: context.texts.bodySmall?.copyWith(
                          color: context.colors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    CategoryPicker(
                      categories: categories,
                      selectedId: state.categoryId,
                      onSelected: _controller.selectCategory,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _DateField(
                      date: state.occurredAt,
                      onPicked: _controller.selectDate,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      label: 'Descrição',
                      hint: 'Opcional',
                      controller: _description,
                      onChanged: _controller.editDescription,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AmountKeypad(
                      onDigit: _controller.pressDigit,
                      onBackspace: _controller.pressBackspace,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Salvar',
              isLoading: state.isSaving,
              onPressed: state.canSave ? _save : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const Key('transaction_delete'),
              label: 'Excluir lançamento',
              variant: AppButtonVariant.ghost,
              onPressed: state.isSaving ? null : _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final saved = await _controller.save();
    if (saved && mounted) Navigator.of(context).pop(true);
  }

  /// Excluir é irreversível e o alvo é dado financeiro do usuário: confirma.
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: const Text('Isso não pode ser desfeito.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_delete'),
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

/// Título mais a procedência do lançamento.
///
/// A procedência importa porque muda o que a edição significa: corrigir algo
/// que você digitou é uma coisa, contrariar o que o banco informou é outra.
class _Header extends StatelessWidget {
  const _Header({required this.transaction});

  final Transaction transaction;

  String get _origin => transaction.isAutomatic
      ? 'Importado do Open Finance'
      : 'Registrado manualmente';

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('Editar lançamento', style: context.texts.titleMedium),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        '$_origin · ${formatDayLabel(transaction.createdAt.toLocal())}',
        textAlign: TextAlign.center,
        style: context.texts.bodySmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
    ],
  );
}

/// Tipo que a folha exibe mas não deixa trocar.
///
/// `savings` e `transfer` não cabem no segmento de duas posições, e trocá-los
/// por despesa/receita perderia a informação que os distingue.
class _FixedType extends StatelessWidget {
  const _FixedType({required this.type});

  final TransactionType type;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: context.tokens.surfaceSunken,
      borderRadius: AppRadii.brMd,
    ),
    child: Text(
      switch (type) {
        TransactionType.savings => 'Poupança',
        TransactionType.transfer => 'Transferência',
        TransactionType.expense => 'Despesa',
        TransactionType.income => 'Receita',
      },
      textAlign: TextAlign.center,
      style: context.texts.titleSmall,
    ),
  );
}

/// Data do lançamento, com seletor nativo.
class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onPicked});

  final DateTime date;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.surfaceSunken,
    borderRadius: AppRadii.brMd,
    child: InkWell(
      key: const Key('transaction_date'),
      borderRadius: AppRadii.brMd,
      onTap: () async {
        final local = date.toLocal();
        final picked = await showDatePicker(
          context: context,
          initialDate: local,
          firstDate: DateTime(2020),
          // Lançamento futuro não é caso de uso: registra-se o que aconteceu.
          lastDate: DateTime.now(),
          helpText: 'Data do lançamento',
        );
        if (picked != null) onPicked(picked);
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: context.tokens.textMuted,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                formatDayLabel(date.toLocal()),
                style: context.texts.titleSmall,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.tokens.textMuted,
            ),
          ],
        ),
      ),
    ),
  );
}
