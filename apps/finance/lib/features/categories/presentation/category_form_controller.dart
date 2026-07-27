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
    @Default(false) bool isSaving,
    String? errorMessage,
  }) = _CategoryFormState;

  const CategoryFormState._();

  /// Nome sem espaço nas pontas — é o que vai para o banco.
  String get trimmedName => name.trim();

  bool get canSave => trimmedName.isNotEmpty && !isSaving;
}

/// Controller da criação de categoria de usuário (RN-1.2).
///
/// Só cria: editar e remover categoria não entram na Fase 0. Remover exige
/// decidir o que acontece com os lançamentos que a usam, e essa é uma pergunta
/// de produto, não de tela.
@riverpod
class CategoryFormController extends _$CategoryFormController {
  @override
  CategoryFormState build() => const CategoryFormState();

  /// Atualiza o nome digitado.
  void editName(String value) =>
      state = state.copyWith(name: value, errorMessage: null);

  /// Escolhe o ícone.
  void selectIcon(String iconKey) => state = state.copyWith(iconKey: iconKey);

  /// Escolhe (ou desmarca) a matiz da paleta.
  void selectColor(int? colorIndex) =>
      state = state.copyWith(colorIndex: colorIndex);

  /// Cria a categoria. Devolve a categoria criada, ou `null` quando falhou.
  Future<Category?> save() async {
    final space = ref.read(activeSpaceProvider);
    if (space == null) {
      state = state.copyWith(
        errorMessage: 'Aguarde a sincronização do seu espaço.',
      );
      return null;
    }
    if (!state.canSave) {
      state = state.copyWith(
        errorMessage: 'Informe um nome para a categoria.',
      );
      return null;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    final result = await ref
        .read(categoriesRepositoryProvider)
        .create(
          spaceId: space.id,
          name: state.trimmedName,
          iconKey: state.iconKey,
          colorIndex: state.colorIndex,
        );

    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => () {
        state = state.copyWith(
          isSaving: false,
          errorMessage: failure.message,
        );
        return null;
      }(),
    };
  }
}
