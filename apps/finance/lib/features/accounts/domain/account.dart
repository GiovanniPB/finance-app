import 'package:freezed_annotation/freezed_annotation.dart';

part 'account.freezed.dart';

/// Entidade de domínio: uma conta financeira do usuário.
///
/// Imutável (freezed). Conversões de/para linhas do PowerSync ficam aqui para
/// manter a camada de dados fina e o mapeamento testável de forma pura.
@freezed
abstract class Account with _$Account {
  const factory Account({
    required String id,
    required String ownerId,
    required String name,
    required String currency,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Account;

  const Account._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  /// Datas são texto ISO-8601; o `id` é a PK implícita do PowerSync.
  factory Account.fromRow(Map<String, Object?> row) => Account(
    id: row['id']! as String,
    ownerId: row['owner_id']! as String,
    name: row['name']! as String,
    currency: row['currency']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );

  /// Colunas para INSERT/UPSERT no banco local (exclui campos derivados).
  Map<String, Object?> toColumns() => {
    'id': id,
    'owner_id': ownerId,
    'name': name,
    'currency': currency,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}
