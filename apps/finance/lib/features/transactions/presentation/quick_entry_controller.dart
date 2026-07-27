import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
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
    DateTime? occurredAt,
    @Default(false) bool isSaving,
    String? errorMessage,
  }) = _QuickEntryState;

  const QuickEntryState._();

  /// Valor como [Money], sempre positivo — o tipo carrega a direção.
  Money get amount => Money.fromMinor(amountMinor);

  /// Texto do valor para exibição, sem símbolo (o `R$` é prefixo fixo na UI).
  String get amountLabel => amount.format(withSymbol: false);

  /// Se dá para salvar: precisa de valor e de categoria.
  bool get canSave => amountMinor > 0 && categoryId != null && !isSaving;
}

/// Controller do registro rápido.
///
/// ## Por que o valor é um acumulador de centavos
///
/// Cada dígito entra pela direita (`1` → `0,01`; `1`,`4` → `0,14`; …). Isso
/// elimina a tecla de vírgula que o mockup previa — e com ela o erro de
/// posicionar o separador decimal, que é o erro mais comum em campo de valor.
/// Uma tecla menos e um caso de erro menos.
@riverpod
class QuickEntryController extends _$QuickEntryController {
  /// Dez dígitos: até R$ 99.999.999,99. Acima disso é erro de digitação, não
  /// caso de uso — e evita estourar o `int`.
  static const _maxDigits = 10;

  @override
  QuickEntryState build() => const QuickEntryState();

  /// Acrescenta um dígito pela direita.
  void pressDigit(int digit) {
    if (state.amountMinor.toString().length >= _maxDigits) return;
    state = state.copyWith(
      amountMinor: state.amountMinor * 10 + digit,
      errorMessage: null,
    );
  }

  /// Remove o último dígito.
  void pressBackspace() {
    state = state.copyWith(
      amountMinor: state.amountMinor ~/ 10,
      errorMessage: null,
    );
  }

  /// Alterna entre despesa e receita.
  void selectType(TransactionType type) => state = state.copyWith(type: type);

  /// Seleciona (ou desmarca) a categoria.
  void selectCategory(String? categoryId) =>
      state = state.copyWith(categoryId: categoryId, errorMessage: null);

  /// Define a data do lançamento.
  void selectDate(DateTime date) => state = state.copyWith(occurredAt: date);

  /// Define a conta do lançamento.
  void selectAccount(String? accountId) =>
      state = state.copyWith(accountId: accountId);

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
          accountId: state.accountId,
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
