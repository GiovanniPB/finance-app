import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';
import '../domain/category.dart';

part 'categories_providers.g.dart';

/// Categorias disponíveis no espaço ativo: as de sistema mais as do espaço.
@riverpod
Stream<List<Category>> categories(Ref ref) {
  final space = ref.watch(activeSpaceProvider);
  if (space == null) return Stream.value(const []);
  return ref.watch(categoriesRepositoryProvider).watchForSpace(space.id);
}

/// Só as categorias **criadas pelo usuário** neste espaço.
///
/// É o que a aba Perfil lista para editar e remover. As dez de sistema ficam
/// fora porque não são editáveis (a RLS bloqueia, e o nome delas é vocabulário
/// compartilhado entre espaços): listá-las numa seção de gerenciamento seria
/// oferecer dez linhas que não respondem ao toque.
@riverpod
List<Category> userCategories(Ref ref) {
  final list =
      ref.watch(categoriesProvider).asData?.value ?? const <Category>[];

  return List.unmodifiable([
    for (final category in list)
      if (!category.isSystem) category,
  ]);
}

/// Índice `id → categoria`, para a lista de transações resolver o nome e o
/// ícone de cada linha sem varrer a lista inteira por transação.
@riverpod
Map<String, Category> categoriesById(Ref ref) {
  final list =
      ref.watch(categoriesProvider).asData?.value ?? const <Category>[];
  return Map.unmodifiable({for (final category in list) category.id: category});
}
