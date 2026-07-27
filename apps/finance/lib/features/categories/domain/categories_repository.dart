import 'package:core/core.dart';

import 'category.dart';

/// Contrato da camada de dados de categorias.
abstract interface class CategoriesRepository {
  /// Stream reativo das categorias disponíveis num espaço: as de **sistema**
  /// (globais) mais as criadas dentro daquele espaço.
  Stream<List<Category>> watchForSpace(String spaceId);

  /// Cria uma categoria de usuário no espaço informado.
  ///
  /// Categoria de sistema nunca é criada pelo cliente — a RLS bloqueia.
  Future<Result<Category, Failure>> create({
    required String spaceId,
    required String name,
    required String iconKey,
    int? colorIndex,
    String? parentCategoryId,
  });

  /// Remove uma categoria de usuário pelo id.
  Future<Result<void, Failure>> delete(String id);
}
