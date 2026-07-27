/// Sistema de design compartilhado: tema, tokens e widgets base.
///
/// A regra que define este sistema: **despesa é o estado neutro**. Um app de
/// despesas mostra despesa em ~90% das linhas; colorir isso é ruído, e
/// vermelho-para-despesa lê como erro na ação mais ordinária do produto. Só
/// receita e orçamento estourado ganham cor, e cor nunca é o único sinal.
library;

export 'src/theme/app_palette.dart';
export 'src/theme/app_spacing.dart';
export 'src/theme/app_theme.dart';
export 'src/theme/app_tokens.dart';
export 'src/theme/app_typography.dart';
export 'src/widgets/app_bottom_nav.dart';
export 'src/widgets/app_button.dart';
export 'src/widgets/app_empty_state.dart';
export 'src/widgets/app_segmented_control.dart';
export 'src/widgets/app_text_field.dart';
export 'src/widgets/balance_header.dart';
export 'src/widgets/budget_progress.dart';
export 'src/widgets/category_chip.dart';
export 'src/widgets/category_swatch.dart';
export 'src/widgets/money_text.dart';
export 'src/widgets/transaction_tile.dart';
