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

  /// Altera nome, ícone e matiz de uma categoria de usuário.
  ///
  /// Categoria de sistema não é editável: o nome dela é vocabulário
  /// compartilhado por todo espaço, e a RLS bloqueia no servidor de qualquer
  /// forma.
  Future<Result<Category, Failure>> update(Category category);

  /// Quantos lançamentos usam esta categoria, em **qualquer** mês.
  ///
  /// Existe para a tela poder dizer "não dá para remover, 12 lançamentos usam
  /// esta categoria" em vez de falhar sem explicar.
  Future<Result<int, Failure>> countUsage(String categoryId);

  /// Remove uma categoria de usuário pelo id.
  ///
  /// **Recusa** categoria com lançamento, com [ValidationFailure]. Apagá-la
  /// deixaria os lançamentos sem categoria, e escolher entre isso e reatribuir
  /// é pergunta de produto, não de tela. O caso resolvido aqui é o trivial: a
  /// categoria criada por engano, que ninguém usou.
  Future<Result<void, Failure>> delete(String id);
}
