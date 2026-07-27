import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/account.dart';
import 'account_icons.dart';

/// Uma conta na lista.
///
/// Mostra o saldo com o sinal já resolvido pelo tipo ([Account.signedBalance]):
/// a fatura do cartão aparece negativa mesmo tendo sido digitada positiva, que
/// é a única leitura que soma certo ao lado das outras contas.
class AccountTile extends StatelessWidget {
  const AccountTile({required this.account, required this.onTap, super.key});

  final Account account;
  final VoidCallback onTap;

  /// Segunda linha: tipo, instituição e os marcadores que valem dizer.
  String _subtitle() => [
    account.type.label,
    ?account.institution,
    if (account.isSavingsTarget) 'Poupança',
    if (account.isSharedWithHousehold) 'Compartilhada',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final balance = account.signedBalance;
    final asOf = formatDayLabel(account.balanceAsOf.toLocal()).toLowerCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surfaceSunken,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  height: 40,
                  width: 40,
                  child: Icon(
                    accountTypeIcon(account.type),
                    size: 20,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Sem cor, nos dois sentidos. Saldo positivo não é receita, e
                  // fatura de cartão não é erro nem estouro de orçamento — são
                  // as duas únicas coisas que ganham cor neste sistema
                  // (`AppTokens`). Pintar toda fatura de vermelho seria o
                  // "vermelho-para-despesa lê como erro" que a regra evita; o
                  // sinal negativo e as figuras tabulares já bastam.
                  MoneyText(balance),
                  const SizedBox(height: AppSpacing.xxs),
                  // Registrar gasto não move o saldo (é snapshot), então o
                  // número precisa dizer de quando é. Sem isso ele envelhece
                  // calado e ninguém percebe.
                  Text(
                    // Minúscula porque a data entra no meio da frase: o rótulo
                    // devolve "Hoje", e "de Hoje" lê como erro de digitação.
                    'de $asOf',
                    style: context.texts.labelSmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
