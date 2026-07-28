import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/open_finance_connection.dart';

/// Uma conexão bancária na lista do Perfil.
///
/// Espelha a `AccountTile` de propósito — mesma altura de toque, mesma
/// hairline, mesma hierarquia de duas linhas. A seção é de gerenciamento, e
/// duas listas de gerenciamento na mesma tela com formas diferentes leriam como
/// duas telas.
class ConnectionTile extends StatelessWidget {
  const ConnectionTile({
    required this.connection,
    required this.accountCount,
    this.onTap,
    super.key,
  });

  final OpenFinanceConnection connection;

  /// Quantas contas esta conexão trouxe. É a resposta à pergunta que o usuário
  /// faz ao olhar a linha: o que este banco entregou?
  final int accountCount;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final needsAction = connection.status.needsUserAction;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.hairline)),
        ),
        child: Row(
          children: [
            // Ícone, não logo do banco: `connector_image_url` vem da Pluggy e
            // carregá-lo exigiria rede numa lista que precisa renderizar
            // offline. Quando houver cache de imagem, entra aqui.
            Icon(
              needsAction
                  ? Icons.error_outline
                  : Icons.account_balance_outlined,
              // **A distinção não é por cor.** Âmbar (`moneyWarning`) pertence
              // ao orçamento e vermelho (`moneyOver`) a limite estourado — usar
              // qualquer um dos dois aqui faria uma conexão parada ler como
              // dinheiro em risco. O que separa os dois estados é a **forma do
              // ícone** e a frase da segunda linha; a cor só sobe de
              // `textMuted` para `textSecondary`, o salto de ênfase usual.
              color: needsAction ? tokens.textSecondary : tokens.textMuted,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connection.displayName,
                    style: context.texts.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _subtitle(),
                    style: context.texts.bodySmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (needsAction) Icon(Icons.chevron_right, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }

  /// Estado da conexão e o que ela trouxe, na mesma linha.
  ///
  /// A contagem só aparece quando há conta: "0 contas" numa conexão que acabou
  /// de nascer leria como falha, quando na verdade a sincronização está em
  /// curso — e o próprio rótulo do status já diz isso.
  String _subtitle() {
    final status = connection.status.label;
    if (accountCount == 0) return status;
    final plural = accountCount == 1 ? 'conta' : 'contas';
    return '$status · $accountCount $plural';
  }
}
