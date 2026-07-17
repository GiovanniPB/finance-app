import 'package:freezed_annotation/freezed_annotation.dart';

part 'space.freezed.dart';

/// Tipo de espaço. Ver ADR 0004 / PRD §4.
enum SpaceType {
  personal,
  household,
  group;

  static SpaceType fromDb(String value) => switch (value) {
    'personal' => SpaceType.personal,
    'household' => SpaceType.household,
    'group' => SpaceType.group,
    _ => throw ArgumentError.value(value, 'space_type', 'Tipo inválido'),
  };

  String get db => name;
}

/// Política de privacidade do espaço.
enum SpacePrivacy {
  fullTransparency,
  sharedOnly;

  static SpacePrivacy fromDb(String value) => switch (value) {
    'full_transparency' => SpacePrivacy.fullTransparency,
    'shared_only' => SpacePrivacy.sharedOnly,
    _ => throw ArgumentError.value(value, 'privacy_policy', 'Valor inválido'),
  };

  String get db => this == SpacePrivacy.fullTransparency
      ? 'full_transparency'
      : 'shared_only';
}

/// Estado do ciclo de vida do espaço.
enum SpaceStatus {
  active,
  archived;

  static SpaceStatus fromDb(String value) => switch (value) {
    'active' => SpaceStatus.active,
    'archived' => SpaceStatus.archived,
    _ => throw ArgumentError.value(value, 'status', 'Status inválido'),
  };

  String get db => name;
}

/// Entidade de domínio: um Espaço (contexto financeiro).
///
/// Imutável (freezed). Conversões de/para linhas do PowerSync ficam aqui para
/// manter a camada de dados fina e o mapeamento testável de forma pura.
@freezed
abstract class Space with _$Space {
  const factory Space({
    required String id,
    required SpaceType type,
    required String name,
    required String ownerId,
    required SpacePrivacy privacy,
    required SpaceStatus status,
    required String settlementCurrency,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? archivedAt,
  }) = _Space;

  const Space._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  factory Space.fromRow(Map<String, Object?> row) => Space(
    id: row['id']! as String,
    type: SpaceType.fromDb(row['space_type']! as String),
    name: row['name']! as String,
    ownerId: row['owner_id']! as String,
    privacy: SpacePrivacy.fromDb(row['privacy_policy']! as String),
    status: SpaceStatus.fromDb(row['status']! as String),
    settlementCurrency: row['settlement_currency']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    archivedAt: row['archived_at'] == null
        ? null
        : DateTime.parse(row['archived_at']! as String),
  );

  /// Colunas para INSERT/UPSERT no banco local.
  Map<String, Object?> toColumns() => {
    'id': id,
    'space_type': type.db,
    'name': name,
    'owner_id': ownerId,
    'privacy_policy': privacy.db,
    'status': status.db,
    'settlement_currency': settlementCurrency,
    'archived_at': archivedAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  bool get isPersonal => type == SpaceType.personal;
  bool get isArchived => status == SpaceStatus.archived;
}
