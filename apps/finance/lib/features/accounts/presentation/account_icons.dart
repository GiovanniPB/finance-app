import 'package:flutter/material.dart';

import '../domain/account.dart';

/// Ícone de cada tipo de conta.
///
/// Fica fora do domínio de propósito: `AccountType` não conhece Flutter (ADR
/// 0003). Material Icons enquanto o set do produto não estiver decidido — é o
/// mesmo compromisso registrado para `CategoryIcons`.
IconData accountTypeIcon(AccountType type) => switch (type) {
  AccountType.checking => Icons.account_balance_outlined,
  AccountType.savings => Icons.savings_outlined,
  AccountType.creditCard => Icons.credit_card_outlined,
  AccountType.investment => Icons.trending_up,
  AccountType.cash => Icons.payments_outlined,
  AccountType.other => Icons.account_balance_wallet_outlined,
};
