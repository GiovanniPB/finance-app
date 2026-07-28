import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../domain/category.dart';
import 'category_icons.dart';

part 'category_form_controller.freezed.dart';
part 'category_form_controller.g.dart';

/// Estado do formulário de nova categoria.
@freezed
abstract class CategoryFormState with _$CategoryFormState {
  const factory CategoryFormState({
    @Default('') String name,

    /// Chave do ícone, sempre uma de [CategoryIcons.selectable].
    @Default('other') String iconKey,

    /// Índice na paleta do design system. Nulo deixa a cor sair do hash do id.
    int? colorIndex,

    /// Categoria em edição. Nula quando é uma categoria nova.
    Category? editing,
    @Default(false) bool isSaving,
    String? errorMessage,
  }) = _CategoryFormState;

  const CategoryFormState._();

  /// Nome sem espaço nas pontas — é o que vai para o banco.
  String get trimmedName => name.trim();

  bool get isEditing => editing != null;

  bool get canSave => trimmedName.isNotEmpty && !isSaving;
}

/// Controller do formulário de categoria de usuário (RN-1.2).
///
/// **Categoria de sistema não passa por aqui.** As dez semeadas são vocabulário
/// compartilhado por todo espaço, e a RLS bloqueia a escrita no servidor — a UI
/// nem as oferece para edição.
///
/// Remover só vale para categoria **sem lançamento algum**: é o caso da
/// categoria criada por engano. O caso "tem lançamento" segue de fora, porque
/// escolher entre deixar os lançamentos sem categoria e reatribuí-los é
/// pergunta de produto, não de tela — e o repository recusa com a contagem na
/// mensagem.
@riverpod
class CategoryFormController extends _$CategoryFormController {
  @override
  CategoryFormState build(Category? editing) {
    // Mantém o espaço ativo assinado enquanto a folha existe — mesmo motivo do
    // `GoalFormController`: `watch` apagaria o que o usuário já digitou quando
    // o espaço chegasse, e sem assinatura nenhuma o `read` do `save()` pegaria
    // o provider frio e falharia com "aguarde a sincronização" havendo espaço.
    ref.listen(activeSpaceProvider, (_, _) {});

    if (editing == null) return const CategoryFormState();

    return CategoryFormState(
      name: editing.name,
      iconKey: editing.iconKey,
      colorIndex: editing.colorIndex,
      editing: editing,
    );
  }

  /// Atualiza o nome digitado.
  void editName(String value) =>
      state = state.copyWith(name: value, errorMessage: null);

  /// Escolhe o ícone.
  void selectIcon(String iconKey) => state = state.copyWith(iconKey: iconKey);

  /// Escolhe (ou desmarca) a matiz da paleta.
  void selectColor(int? colorIndex) =>
      state = state.copyWith(colorIndex: colorIndex);

  /// Cria ou salva a categoria. Devolve a gravada, ou `null` se falhou.
  Future<Category?> save() async {
    if (!state.canSave) {
      state = state.copyWith(
        errorMessage: 'Informe um nome para a categoria.',
      );
      return null;
    }

    final repository = ref.read(categoriesRepositoryProvider);
    final editing = state.editing;

    // Só criar precisa do espaço: editar mexe numa linha que já o tem, e exigir
    // sincronização para renomear seria travar o caminho sem motivo.
    if (editing == null) {
      final space = ref.read(activeSpaceProvider);
      if (space == null) {
        state = state.copyWith(
          errorMessage: 'Aguarde a sincronização do seu espaço.',
        );
        return null;
      }
      state = state.copyWith(isSaving: true, errorMessage: null);

      return _unwrap(
        await repository.create(
          spaceId: space.id,
          name: state.trimmedName,
          iconKey: state.iconKey,
          colorIndex: state.colorIndex,
        ),
      );
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    return _unwrap(
      await repository.update(
        editing.copyWith(
          name: state.trimmedName,
          iconKey: state.iconKey,
          colorIndex: state.colorIndex,
        ),
      ),
    );
  }

  /// Remove a categoria em edição. Devolve `true` quando saiu.
  ///
  /// Falha esperada e não excepcional: categoria com lançamento. O repository
  /// devolve a contagem na mensagem, e ela aparece na folha em vez de num
  /// diálogo que já fechou.
  Future<bool> remove() async {
    final editing = state.editing;
    if (editing == null) return false;

    state = state.copyWith(isSaving: true, errorMessage: null);

    final result = await ref
        .read(categoriesRepositoryProvider)
        .delete(editing.id);

    return switch (result) {
      Ok() => true,
      Err(:final failure) => () {
        state = state.copyWith(isSaving: false, errorMessage: failure.message);
        return false;
      }(),
    };
  }

  Category? _unwrap(Result<Category, Failure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => () {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return null;
    }(),
  };
}
