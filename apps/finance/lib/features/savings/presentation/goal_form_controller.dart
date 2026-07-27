import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../domain/savings_goal.dart';
import '../domain/savings_repository.dart';

part 'goal_form_controller.freezed.dart';
part 'goal_form_controller.g.dart';

/// Percentual inicial da meta percentual.
///
/// Constante de nível de arquivo, e não membro estático da classe: o freezed
/// copia o literal de `@Default(...)` para dentro do arquivo gerado, e um
/// `static` privado da classe não é visível de lá. `dart analyze` não pega isso
/// — só o compilador, ao rodar o teste.
const _defaultPercentage = 20;

/// Passo da folha de meta.
enum GoalFormStep {
  /// Escolher o tipo. Cada tipo pede campos diferentes, e um formulário que
  /// mostrasse a união deles não caberia na tela com o teclado aberto.
  type,

  /// Preencher os campos daquele tipo.
  details,
}

/// Estado do formulário de meta.
@freezed
abstract class GoalFormState with _$GoalFormState {
  const factory GoalFormState({
    /// [SavingsGoalType.objective] já vem escolhido: é o tipo mais comum, e uma
    /// tela de escolha sem nada marcado obriga um toque a mais para o caso
    /// dominante.
    @Default(SavingsGoalType.objective) SavingsGoalType type,
    @Default(GoalFormStep.type) GoalFormStep step,
    @Default('') String name,

    /// Se o nome foi digitado. Distingue "ainda não escrevi" de "escrevi isto":
    /// sem a marca, a sugestão automática sobrescreveria o que o usuário
    /// escolheu — mesma razão do `accountTouched` no registro rápido.
    @Default(false) bool nameTouched,

    /// Valor em centavos, preenchido da direita para a esquerda.
    @Default(0) int amountMinor,
    @Default(_defaultPercentage) int percentage,
    DateTime? targetDate,
    String? linkedAccountId,

    /// Meta em edição. Nula quando é uma meta nova.
    SavingsGoal? editing,
    @Default(false) bool isSaving,
    String? errorMessage,
  }) = _GoalFormState;

  const GoalFormState._();

  bool get isEditing => editing != null;

  Money get amount => Money.fromMinor(amountMinor);

  /// Texto do valor para o campo de exibição, sem símbolo.
  String get amountLabel => amount.format(withSymbol: false);

  /// Se o tipo escolhido pede um valor em dinheiro.
  bool get needsAmount => type != SavingsGoalType.percentageIncome;

  /// Se o tipo escolhido aceita prazo. Só meta por objetivo — valor fixo mensal
  /// e percentual já têm o mês como período.
  bool get acceptsDeadline => type == SavingsGoalType.objective;

  /// Nome efetivo: o digitado, ou a sugestão do tipo quando nada foi
  /// digitado.
  String get effectiveName => nameTouched && name.trim().isNotEmpty
      ? name.trim()
      : suggestedName ?? name.trim();

  /// Sugestão de nome, quando o tipo determina um.
  ///
  /// Só a meta percentual tem: "20% da renda" é a descrição completa dela. Um
  /// objetivo ou um valor fixo podem ser qualquer coisa, e inventar "Meta de R$
  /// 500" seria pior que um campo vazio.
  String? get suggestedName =>
      type == SavingsGoalType.percentageIncome ? '$percentage% da renda' : null;

  bool get canSave {
    if (isSaving || effectiveName.isEmpty) return false;
    return needsAmount ? amountMinor > 0 : percentage >= 1 && percentage <= 100;
  }
}

/// Controller da folha de meta.
///
/// ## Por que dois passos
///
/// Os três tipos pedem campos diferentes, e a união deles (nome, valor,
/// percentual, prazo, conta) mais o teclado numérico não cabe numa folha só — é
/// literalmente o defeito já catalogado na folha de editar conta, onde a última
/// fileira do teclado fica cortada. Separar a escolha do tipo resolve o espaço
/// **e** deixa cada passo com uma pergunta só.
///
/// A meta a editar entra como argumento do provider (`null` = nova), e não por
/// um `load()` imperativo: o formulário já nasce preenchido, sem um primeiro
/// frame zerado.
@riverpod
class GoalFormController extends _$GoalFormController {
  @override
  GoalFormState build(SavingsGoal? editing) {
    // Mantém o espaço ativo assinado enquanto a folha existe. É `listen`, e não
    // `watch`, de propósito: `watch` reconstruiria o estado quando o espaço
    // chegasse, apagando o que o usuário já digitou. Sem assinatura nenhuma, o
    // `ref.read` do `save()` pega o provider frio — o stream não emitiu, o
    // espaço lê como nulo e o Salvar falha com "aguarde a sincronização" mesmo
    // havendo espaço. Assinar aqui faz o tempo de preenchimento do formulário
    // valer como espera.
    ref.listen(activeSpaceProvider, (_, _) {});

    if (editing == null) return const GoalFormState();

    return GoalFormState(
      // Editar já começa nos detalhes: o tipo é identidade da meta e não muda
      // (trocar o tipo mudaria o significado do histórico de contribuições).
      step: GoalFormStep.details,
      type: editing.type,
      name: editing.name,
      nameTouched: true,
      amountMinor: editing.targetAmountMinor ?? 0,
      percentage: editing.percentage ?? _defaultPercentage,
      targetDate: editing.targetDate,
      linkedAccountId: editing.linkedAccountId,
      editing: editing,
    );
  }

  void selectType(SavingsGoalType type) =>
      state = state.copyWith(type: type, errorMessage: null);

  void goToDetails() =>
      state = state.copyWith(step: GoalFormStep.details, errorMessage: null);

  void backToType() =>
      state = state.copyWith(step: GoalFormStep.type, errorMessage: null);

  void setName(String value) => state = state.copyWith(
    name: value,
    nameTouched: true,
    errorMessage: null,
  );

  void pressDigit(int digit) => state = state.copyWith(
    amountMinor: MinorDigits.append(state.amountMinor, digit),
    errorMessage: null,
  );

  void pressBackspace() => state = state.copyWith(
    amountMinor: MinorDigits.removeLast(state.amountMinor),
    errorMessage: null,
  );

  void setPercentage(int value) =>
      state = state.copyWith(percentage: value, errorMessage: null);

  void setTargetDate(DateTime? date) =>
      state = state.copyWith(targetDate: date, errorMessage: null);

  /// Marca (ou desmarca) a conta onde o dinheiro fica.
  void selectAccount(String? accountId) => state = state.copyWith(
    linkedAccountId: state.linkedAccountId == accountId ? null : accountId,
    errorMessage: null,
  );

  /// Persiste a meta. Devolve `true` quando salvou.
  Future<bool> save() async {
    if (!state.canSave) {
      state = state.copyWith(errorMessage: _whyCannotSave());
      return false;
    }

    final repository = ref.read(savingsRepositoryProvider);
    state = state.copyWith(isSaving: true, errorMessage: null);

    final editing = state.editing;
    final result = editing == null
        ? await _create(repository)
        : await repository.updateGoal(
            editing.copyWith(
              name: state.effectiveName,
              targetAmountMinor: state.needsAmount ? state.amountMinor : null,
              targetDate: state.acceptsDeadline ? state.targetDate : null,
              percentage: state.needsAmount ? null : state.percentage,
              linkedAccountId: state.linkedAccountId,
            ),
          );

    return switch (result) {
      Ok() => true,
      Err(:final failure) => _fail(failure),
    };
  }

  Future<Result<SavingsGoal, Failure>> _create(
    SavingsRepository repository,
  ) async {
    final space = ref.read(activeSpaceProvider);
    if (space == null) {
      return const Err(
        SyncFailure('Aguarde a sincronização do seu espaço.'),
      );
    }

    return repository.createGoal(
      spaceId: space.id,
      type: state.type,
      name: state.effectiveName,
      targetAmount: state.needsAmount ? state.amount : null,
      targetDate: state.acceptsDeadline ? state.targetDate : null,
      percentage: state.needsAmount ? null : state.percentage,
      linkedAccountId: state.linkedAccountId,
    );
  }

  /// Remove a meta em edição. Devolve `true` quando removeu.
  Future<bool> remove() async {
    final editing = state.editing;
    if (editing == null) return false;

    state = state.copyWith(isSaving: true, errorMessage: null);

    final result = await ref
        .read(savingsRepositoryProvider)
        .deleteGoal(editing.id);

    return switch (result) {
      Ok() => true,
      Err(:final failure) => _fail(failure),
    };
  }

  /// A frase que diz o que falta, em vez de um botão desabilitado sem
  /// explicação.
  String _whyCannotSave() {
    if (state.effectiveName.isEmpty) return 'Dê um nome para a meta.';
    if (state.needsAmount && state.amountMinor == 0) {
      return 'Informe um valor maior que zero.';
    }
    return 'O percentual deve ficar entre 1 e 100.';
  }

  bool _fail(Failure failure) {
    state = state.copyWith(isSaving: false, errorMessage: failure.message);
    return false;
  }
}
