import 'package:flutter/material.dart';

/// Traduz o `icon_key` da categoria em um [IconData].
///
/// O banco guarda uma **chave estável** (`food`, `transport`…), nunca o
/// codepoint da fonte: codepoint amarraria o dado a uma versão específica do
/// set de ícones, e trocar de set invalidaria todas as linhas.
///
/// Chave desconhecida cai em [fallback] em vez de estourar — categoria vinda de
/// uma versão mais nova do app não deve quebrar a lista.
abstract final class CategoryIcons {
  static const IconData fallback = Icons.label_outline;

  static const _map = <String, IconData>{
    'food': Icons.restaurant_outlined,
    'transport': Icons.directions_bus_outlined,
    'home': Icons.home_outlined,
    'health': Icons.favorite_outline,
    'leisure': Icons.movie_outlined,
    'education': Icons.school_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'subscriptions': Icons.subscriptions_outlined,
    'salary': Icons.payments_outlined,
    'other': Icons.label_outline,
  };

  /// Ícone da chave informada, ou [fallback] quando desconhecida.
  static IconData resolve(String? iconKey) => _map[iconKey] ?? fallback;

  /// Ícone usado quando a transação não tem categoria.
  static const IconData uncategorized = Icons.help_outline;

  /// Ícone de receita — não é categoria, é o tipo da transação.
  static const IconData income = Icons.arrow_downward;
}
