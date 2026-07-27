import 'package:freezed_annotation/freezed_annotation.dart';

part 'category.freezed.dart';

/// Entidade de domínio: categoria de transação (PRD §5.2, RN-1.2).
///
/// Categoria de **sistema** ([isSystem]) é global — não pertence a espaço
/// algum e está sempre disponível. Categoria criada pelo usuário pertence a um
/// espaço; a migration garante a exclusividade por check constraint.
///
/// [colorIndex] é um índice na paleta do design system, **não** um hex: o
/// sistema restringe categoria a seis matizes de baixa croma para nenhuma
/// categoria gritar mais alto que um valor. `null` deixa o design system
/// derivar a cor do hash do [id].
@freezed
abstract class Category with _$Category {
  const factory Category({
    required String id,
    required String name,
    required String iconKey,
    required bool isSystem,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? spaceId,
    int? colorIndex,
    String? parentCategoryId,
  }) = _Category;

  const Category._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  ///
  /// O PowerSync não tem tipo booleano: `is_system` chega como inteiro 0/1.
  factory Category.fromRow(Map<String, Object?> row) => Category(
    id: row['id']! as String,
    name: row['name']! as String,
    iconKey: row['icon_key']! as String,
    isSystem: (row['is_system'] as int? ?? 0) != 0,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    spaceId: row['space_id'] as String?,
    colorIndex: row['color_index'] as int?,
    parentCategoryId: row['parent_category_id'] as String?,
  );

  /// Colunas para INSERT/UPDATE no banco local.
  Map<String, Object?> toColumns() => {
    'id': id,
    'space_id': spaceId,
    'name': name,
    'icon_key': iconKey,
    'color_index': colorIndex,
    'is_system': isSystem ? 1 : 0,
    'parent_category_id': parentCategoryId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// Subcategoria de outra categoria.
  bool get isChild => parentCategoryId != null;
}
