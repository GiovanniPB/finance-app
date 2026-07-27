import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../domain/transaction.dart';

part 'transaction_edit_controller.freezed.dart';
part 'transaction_edit_controller.g.dart';

/// Estado do formulário de edição de um lançamento.
@freezed
abstract class TransactionEditState with _$TransactionEditState {
  const factory TransactionEditState({
    required TransactionType type,
    required DateTime occurredAt,

    /// Valor **absoluto** em centavos. A direção mora em [type].
    @Default(0) int amountMinor,
    String? categoryId,
    String? description,
    @Default(false) bool isSaving,
    String? errorMessage,
  }) = _TransactionEditState;

  const TransactionEditState._();

  /// Valor com o sinal do domínio: saída é negativa (ver `Transaction`).
  Money get amount =>
      Money.fromMinor(type.isOutflow ? -amountMinor : amountMinor);

  /// Texto do valor para exibição, sem símbolo nem sinal.
  String get amountLabel =>
      Money.fromMinor(amountMinor).format(withSymbol: false);

  /// Se o tipo é editável por segmento Despesa/Receita.
  ///
  /// `savings` e `transfer` não entram no segmento: o segmento só sabe duas
  /// posições, e mostrá-lo mudaria o tipo em silêncio no primeiro toque.
  bool get canSwitchType =>
      type == TransactionType.expense || type == TransactionType.income;

  bool get canSave => amountMinor > 0 && !isSaving;
}

/// Controller da edição de um lançamento.
///
/// O lançamento entra como argumento do provider, então o formulário nasce
/// preenchido com o que está gravado. Categoria fica opcional aqui — diferente
/// do registro rápido, onde é obrigatória: lançamento importado do Open Finance
/// chega sem categoria, e forçar uma na edição impediria corrigir o valor de um
/// lançamento que ainda não se sabe classificar.
@riverpod
class TransactionEditController extends _$TransactionEditController {
  @override
  TransactionEditState build(Transaction transaction) => TransactionEditState(
    type: transaction.type,
    occurredAt: transaction.occurredAt,
    amountMinor: transaction.amount.amountMinor.abs(),
    categoryId: transaction.categoryId,
    description: transaction.description,
  );

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
      state = state.copyWith(categoryId: categoryId);

  /// Define a data do lançamento.
  void selectDate(DateTime date) => state = state.copyWith(occurredAt: date);

  /// Define a descrição. Texto em branco volta a ser ausência de descrição.
  void editDescription(String value) {
    final trimmed = value.trim();
    state = state.copyWith(description: trimmed.isEmpty ? null : trimmed);
  }

  /// Persiste as mudanças. Devolve `true` quando salvou.
  Future<bool> save() async {
    if (!state.canSave) {
      state = state.copyWith(
        errorMessage: 'Informe um valor maior que zero.',
      );
      return false;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    final result = await ref
        .read(transactionsRepositoryProvider)
        .update(
          transaction.copyWith(
            type: state.type,
            amount: state.amount,
            occurredAt: state.occurredAt,
            categoryId: state.categoryId,
            description: state.description,
          ),
        );

    return switch (result) {
      Ok() => true,
      Err(:final failure) => _fail(failure),
    };
  }

  /// Exclui o lançamento. Devolve `true` quando excluiu.
  Future<bool> remove() async {
    state = state.copyWith(isSaving: true, errorMessage: null);

    final result = await ref
        .read(transactionsRepositoryProvider)
        .delete(transaction.id);

    return switch (result) {
      Ok() => true,
      Err(:final failure) => _fail(failure),
    };
  }

  bool _fail(Failure failure) {
    state = state.copyWith(isSaving: false, errorMessage: failure.message);
    return false;
  }
}
