import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/budget.dart';

part 'budget_form_controller.freezed.dart';
part 'budget_form_controller.g.dart';

/// Estado do formulário de orçamento.
@freezed
abstract class BudgetFormState with _$BudgetFormState {
  const factory BudgetFormState({
    /// Limite em centavos, preenchido da direita para a esquerda.
    @Default(0) int amountMinor,
    String? categoryId,

    /// Id do orçamento sendo editado. Nulo quando é um limite novo.
    String? editingId,
    @Default(false) bool isSaving,
    String? errorMessage,
  }) = _BudgetFormState;

  const BudgetFormState._();

  /// Limite como [Money].
  Money get limit => Money.fromMinor(amountMinor);

  /// Texto do limite para exibição, sem símbolo.
  String get amountLabel => limit.format(withSymbol: false);

  bool get isEditing => editingId != null;

  /// Precisa de limite e de categoria.
  bool get canSave => amountMinor > 0 && categoryId != null && !isSaving;
}

/// Controller do formulário de orçamento.
///
/// ## Vigência: reorçar não reescreve o passado
///
/// Salvar grava `starts_at` no **mês em foco**. Mudar o limite em julho cria
/// uma linha nova a partir de julho e deixa junho como estava — a comparação
/// de "quanto eu tinha orçado" continua honesta mês a mês. Salvar duas vezes
/// no mesmo mês substitui o limite, sem duplicar (ver
/// `BudgetsRepository.upsert`).
///
/// O orçamento a editar entra como argumento do provider (`null` = novo), e
/// não por um `load()` imperativo: o formulário já nasce preenchido, sem um
/// primeiro frame zerado, e novo e edição são estados independentes.
@riverpod
class BudgetFormController extends _$BudgetFormController {
  @override
  BudgetFormState build(Budget? editing) => editing == null
      ? const BudgetFormState()
      : BudgetFormState(
          amountMinor: editing.limit.amountMinor,
          categoryId: editing.categoryId,
          editingId: editing.id,
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

  /// Seleciona (ou desmarca) a categoria orçada.
  void selectCategory(String? categoryId) =>
      state = state.copyWith(categoryId: categoryId, errorMessage: null);

  /// Persiste o limite. Devolve `true` quando salvou.
  Future<bool> save() async {
    final space = ref.read(activeSpaceProvider);
    if (space == null) {
      state = state.copyWith(
        errorMessage: 'Aguarde a sincronização do seu espaço.',
      );
      return false;
    }
    final categoryId = state.categoryId;
    if (categoryId == null || !state.canSave) {
      state = state.copyWith(
        errorMessage: state.amountMinor == 0
            ? 'Informe um limite maior que zero.'
            : 'Escolha uma categoria.',
      );
      return false;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    final month = ref.read(focusedMonthProvider);
    final result = await ref
        .read(budgetsRepositoryProvider)
        .upsert(
          spaceId: space.id,
          categoryId: categoryId,
          limit: state.limit,
          startsAt: DateTime(month.year, month.month),
        );

    return switch (result) {
      Ok() => true,
      Err(:final failure) => _fail(failure),
    };
  }

  /// Remove o orçamento em edição. Devolve `true` quando removeu.
  Future<bool> remove() async {
    final editingId = state.editingId;
    if (editingId == null) return false;

    state = state.copyWith(isSaving: true, errorMessage: null);

    final result = await ref.read(budgetsRepositoryProvider).delete(editingId);

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
