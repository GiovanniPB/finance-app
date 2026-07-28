import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../domain/open_finance_connection.dart';
import 'connect_bank_page.dart';

/// Ações de uma conexão bancária.
///
/// **Por que uma folha, e não um item na linha.** Gerenciamento neste app mora
/// em folha: conta, orçamento, categoria e meta todos abrem uma. Pendurar
/// "Remover" na própria linha exigiria um gesto — arrastar, ou pressionar e
/// segurar — que esconderia uma ação destrutiva atrás de algo que ninguém
/// descobre, e não existe `Dismissible` em lugar nenhum do produto.
///
/// A folha também resolve o que a linha não conseguia dizer: antes, só conexão
/// que pedia ação respondia ao toque, então uma conexão saudável era um item de
/// lista inerte. Agora todas abrem, e o que muda é quantas ações aparecem.
class ConnectionSheet extends ConsumerStatefulWidget {
  const ConnectionSheet({
    required this.connection,
    required this.accountCount,
    super.key,
  });

  final OpenFinanceConnection connection;
  final int accountCount;

  /// Abre a folha. Devolve `true` quando a conexão foi removida.
  static Future<bool?> show(
    BuildContext context, {
    required OpenFinanceConnection connection,
    required int accountCount,
  }) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ConnectionSheet(
      connection: connection,
      accountCount: accountCount,
    ),
  );

  @override
  ConsumerState<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends ConsumerState<ConnectionSheet> {
  bool _isRemoving = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final connection = widget.connection;

    return Padding(
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
            connection.displayName,
            textAlign: TextAlign.center,
            style: context.texts.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _subtitle(),
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (connection.status.needsUserAction)
            AppButton(
              key: const Key('connection_reconnect'),
              label: 'Reconectar',
              onPressed: _isRemoving
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      unawaited(
                        ConnectBankPage.show(
                          context,
                          updateItemId: connection.itemId,
                        ),
                      );
                    },
            ),
          if (connection.status.needsUserAction)
            const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const Key('connection_remove'),
            label: 'Remover banco',
            variant: AppButtonVariant.ghost,
            isLoading: _isRemoving,
            onPressed: _isRemoving ? null : _confirmRemoval,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _errorMessage!,
              key: const Key('connection_remove_error'),
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle() {
    final status = widget.connection.status.label;
    if (widget.accountCount == 0) return status;
    final plural = widget.accountCount == 1 ? 'conta' : 'contas';
    return '$status · ${widget.accountCount} $plural';
  }

  /// A confirmação **nomeia os dois efeitos**, porque eles surpreendem em
  /// direções opostas.
  ///
  /// O que fica: contas e lançamentos. A FK é `on delete set null`, então as
  /// contas viram contas comuns com o histórico intacto — e quem espera que
  /// "remover o banco" apague o extrato precisa ler isso antes de tocar.
  ///
  /// O que acaba: o acesso no banco, de verdade. É o efeito que ninguém
  /// adivinha ser reversível-só-reconectando, e o que justifica a frase
  /// mencionar o banco em vez de falar só do app.
  Future<void> _confirmRemoval() async {
    final plural = widget.accountCount == 1 ? 'A conta' : 'As contas';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover este banco?'),
        content: Text(
          'O acesso aos seus dados é cancelado no banco. '
          '${widget.accountCount == 0 ? 'As contas' : plural} e os lançamentos '
          'que já chegaram continuam aqui, sem receber novidades. '
          'Para voltar a sincronizar, é preciso conectar de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_remove_connection'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _remove();
  }

  /// Revoga primeiro, apaga depois — e **só** apaga se a revogação passou.
  ///
  /// Na ordem inversa, a linha sairia do app com o consentimento vivo no banco
  /// e sem nada que apontasse para ele: a tela teria dito que o acesso foi
  /// cancelado, e não haveria mais como cancelá-lo.
  Future<void> _remove() async {
    setState(() {
      _isRemoving = true;
      _errorMessage = null;
    });

    final repository = ref.read(openFinanceRepositoryProvider);
    final revoked = await repository.revokeAccess(widget.connection.id);

    // Revogar primeiro; apagar a linha **só** se a revogação passou.
    final failure = switch (revoked) {
      Err(:final failure) => failure,
      Ok() => switch (await repository.delete(widget.connection.id)) {
        Err(:final failure) => failure,
        Ok() => null,
      },
    };

    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _isRemoving = false;
        _errorMessage = failure.message;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }
}
