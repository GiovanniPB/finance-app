import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../domain/account.dart';

part 'account_form_controller.freezed.dart';
part 'account_form_controller.g.dart';

/// Estado do formulário de conta.
@freezed
abstract class AccountFormState with _$AccountFormState {
  const factory AccountFormState({
    @Default('') String name,
    @Default('') String institution,
    @Default(AccountType.checking) AccountType type,

    /// Saldo em centavos, preenchido da direita para a esquerda. Sempre
    /// positivo — a direção vem de [type] (ver [Account]).
    @Default(0) int balanceMinor,
    @Default(false) bool isSavingsTarget,

    /// Household ao qual a conta fica visível. Nulo = só o dono vê.
    String? linkedSpaceId,

    /// Conta sendo editada. Nulo quando é uma conta nova.
    Account? editing,
    @Default(false) bool isSaving,
    String? errorMessage,
  }) = _AccountFormState;

  const AccountFormState._();

  /// Nome sem espaço nas pontas — é o que vai para o banco.
  String get trimmedName => name.trim();

  /// Saldo como [Money], na moeda da conta em edição ou no padrão.
  Money get balance => Money.fromMinor(
    balanceMinor,
    currency: editing?.currency ?? Money.brl,
  );

  /// Texto do saldo para exibição, sem símbolo.
  String get balanceLabel => balance.format(withSymbol: false);

  /// O que o número do saldo significa, que depende do tipo.
  String get balanceHint =>
      type.isDebt ? 'Fatura atual — o quanto você deve' : 'Saldo de hoje';

  bool get isEditing => editing != null;

  bool get canSave => trimmedName.isNotEmpty && !isSaving;
}

/// Controller do formulário de conta (criar e editar).
///
/// A conta a editar entra como argumento do provider (`null` = nova), o mesmo
/// desenho de `BudgetFormController`: o formulário nasce preenchido, sem um
/// primeiro frame zerado, e novo e edição são estados independentes.
///
/// **Saldo é snapshot, não soma de lançamento.** O usuário informa quanto tem
/// hoje; nada aqui recalcula a partir de `transactions`. Ver a doc de
/// [Account] para o porquê.
@riverpod
class AccountFormController extends _$AccountFormController {
  @override
  AccountFormState build(Account? editing) => editing == null
      ? const AccountFormState()
      : AccountFormState(
          name: editing.name,
          institution: editing.institution ?? '',
          type: editing.type,
          balanceMinor: editing.currentBalance.amountMinor.abs(),
          isSavingsTarget: editing.isSavingsTarget,
          linkedSpaceId: editing.linkedSpaceId,
          editing: editing,
        );

  /// Atualiza o nome digitado.
  void editName(String value) =>
      state = state.copyWith(name: value, errorMessage: null);

  /// Atualiza a instituição digitada.
  void editInstitution(String value) =>
      state = state.copyWith(institution: value, errorMessage: null);

  /// Escolhe o tipo da conta.
  void selectType(AccountType type) =>
      state = state.copyWith(type: type, errorMessage: null);

  /// Acrescenta um dígito ao saldo, pela direita.
  void pressDigit(int digit) => state = state.copyWith(
    balanceMinor: MinorDigits.append(state.balanceMinor, digit),
    errorMessage: null,
  );

  /// Remove o último dígito do saldo.
  void pressBackspace() => state = state.copyWith(
    balanceMinor: MinorDigits.removeLast(state.balanceMinor),
    errorMessage: null,
  );

  /// Marca (ou desmarca) a conta como destino de poupança.
  // ignore: avoid_positional_boolean_parameters
  void toggleSavingsTarget(bool value) =>
      state = state.copyWith(isSavingsTarget: value);

  /// Vincula (ou desvincula) a conta a um household.
  void selectLinkedSpace(String? spaceId) =>
      state = state.copyWith(linkedSpaceId: spaceId);

  /// Persiste a conta. Devolve a conta salva, ou `null` quando falhou.
  Future<Account?> save() async {
    if (!state.canSave) {
      state = state.copyWith(errorMessage: 'Informe um nome para a conta.');
      return null;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    final repository = ref.read(accountsRepositoryProvider);
    final editing = state.editing;
    final result = editing == null
        ? await repository.create(
            name: state.trimmedName,
            type: state.type,
            currentBalance: state.balance,
            isSavingsTarget: state.isSavingsTarget,
            institution: state.institution,
            linkedSpaceId: state.linkedSpaceId,
          )
        : await repository.update(
            editing.copyWith(
              name: state.trimmedName,
              type: state.type,
              currentBalance: state.balance,
              isSavingsTarget: state.isSavingsTarget,
              institution: state.institution,
              linkedSpaceId: state.linkedSpaceId,
            ),
          );

    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => _fail(failure),
    };
  }

  /// Remove a conta em edição. Devolve `true` quando removeu.
  Future<bool> remove() async {
    final editing = state.editing;
    if (editing == null) return false;

    state = state.copyWith(isSaving: true, errorMessage: null);

    final result = await ref
        .read(accountsRepositoryProvider)
        .delete(
          editing.id,
        );

    return switch (result) {
      Ok() => true,
      Err(:final failure) => () {
        _fail(failure);
        return false;
      }(),
    };
  }

  Account? _fail(Failure failure) {
    state = state.copyWith(isSaving: false, errorMessage: failure.message);
    return null;
  }
}
