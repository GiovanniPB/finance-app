import 'package:flutter/material.dart';

import '../domain/savings_goal.dart';

/// Ícones do Pilar 3.
///
/// Meta usa o swatch da **marca**, não a paleta de categorias: matiz de
/// categoria é codificação de dado (cada categoria tem a sua, ver
/// `AppTokens.categoryPalette`), e emprestá-la para meta diria que meta é uma
/// categoria. Todas as metas compartilham o mesmo tom, e o ícone distingue o
/// tipo.
abstract final class GoalIcons {
  static IconData forType(SavingsGoalType type) => switch (type) {
    SavingsGoalType.objective => Icons.flag_outlined,
    SavingsGoalType.fixedAmount => Icons.repeat_rounded,
    SavingsGoalType.percentageIncome => Icons.percent_rounded,
  };

  /// Ícone da aba e do estado vazio: um alvo. O cofrinho já é o ícone de
  /// `AccountType.savings`, e reusá-lo confundiria conta com meta.
  static const IconData tab = Icons.track_changes_outlined;
}
