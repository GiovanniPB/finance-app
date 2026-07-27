import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../accounts/presentation/accounts_providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../domain/transaction.dart';

part 'quick_entry_controller.freezed.dart';
part 'quick_entry_controller.g.dart';

/// Estado do formulário de registro rápido.
@freezed
abstract class QuickEntryState with _$QuickEntryState {
  const factory QuickEntryState({
    /// Valor acumulado em centavos, preenchido da direita para a esquerda.
    @Default(0) int amountMinor,
    @Default(TransactionType.expense) TransactionType type,
    String? categoryId,
    String? accountId,

    /// Se o usuário já mexeu no campo de conta.
    ///
    /// Sem isto, `accountId` nulo seria ambíguo: "ainda não escolhi" e "tirei a
    /// conta de propósito" são estados diferentes, e o padrão de conta única
    /// não pode reverter uma escolha explícita de deixar sem conta.
    @Default(false) bool accountTouched,
    DateTime? occurredAt,
    @Default(false) bool isSaving,
    String? errorMessage,
  }) = _QuickEntryState;

  const QuickEntryState._();

  /// Conta que vale para este lançamento: a escolhida, ou a conta única do
  /// espaço (`soleAccountIdProvider`) enquanto ninguém escolheu nada.
  ///
  /// A tela usa isto para marcar o chip e o `save` para gravar — assim o que
  /// aparece selecionado é sempre o que vai para o banco.
  String? effectiveAccountId(String? soleAccountId) =>
      accountTouched ? accountId : soleAccountId;

  /// Valor como [Money], sempre positivo — o tipo carrega a direção.
  Money get amount => Money.fromMinor(amountMinor);

  /// Texto do valor para exibição, sem símbolo (o `R$` é prefixo fixo na UI).
  String get amountLabel => amount.format(withSymbol: false);

  /// Se dá para salvar: precisa de valor e de categoria.
  bool get canSave => amountMinor > 0 && categoryId != null && !isSaving;
}

/// Controller do registro rápido.
///
/// O valor é um acumulador de centavos ([MinorDigits]): cada dígito entra pela
/// direita, o que elimina a tecla de vírgula que o mockup previa — e com ela o
/// erro de posicionar o separador decimal.
@riverpod
class QuickEntryController extends _$QuickEntryController {
  @override
  QuickEntryState build() => const QuickEntryState();

  /// Acrescenta um dígito pela direita.
  void pressDigit(int digit) => state = state.copyWith(
    amountMinor: MinorDigits.append(state.amountMinor, digit),
    errorMessage: null,
  );

  /// Remove o último dígito.
  void pressBackspace() => state = state.copyWith(
    amountMinor: MinorDigits.removeLast(state.amountMinor),
    errorMessage: null,
  );

  /// Alterna entre despesa e receita.
  void selectType(TransactionType type) => state = state.copyWith(type: type);

  /// Seleciona (ou desmarca) a categoria.
  void selectCategory(String? categoryId) =>
      state = state.copyWith(categoryId: categoryId, errorMessage: null);

  /// Define a data do lançamento.
  void selectDate(DateTime date) => state = state.copyWith(occurredAt: date);

  /// Define (ou tira) a conta do lançamento.
  void selectAccount(String? accountId) =>
      state = state.copyWith(accountId: accountId, accountTouched: true);

  /// Persiste a transação. Devolve `true` quando salvou.
  ///
  /// A data em branco vira "agora" — o campo é pré-preenchido na UI justamente
  /// para o caminho mínimo ser valor + categoria + salvar.
  Future<bool> save() async {
    final space = ref.read(activeSpaceProvider);
    if (space == null) {
      state = state.copyWith(
        errorMessage: 'Aguarde a sincronização do seu espaço.',
      );
      return false;
    }
    if (!state.canSave) {
      state = state.copyWith(
        errorMessage: state.amountMinor == 0
            ? 'Informe um valor maior que zero.'
            : 'Escolha uma categoria.',
      );
      return false;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    final result = await ref
        .read(transactionsRepositoryProvider)
        .create(
          spaceId: space.id,
          type: state.type,
          amount: state.amount,
          occurredAt: state.occurredAt ?? DateTime.now(),
          categoryId: state.categoryId,
          accountId: state.effectiveAccountId(ref.read(soleAccountIdProvider)),
        );

    return switch (result) {
      Ok() => true,
      Err(:final failure) => () {
        state = state.copyWith(
          isSaving: false,
          errorMessage: failure.message,
        );
        return false;
      }(),
    };
  }
}
