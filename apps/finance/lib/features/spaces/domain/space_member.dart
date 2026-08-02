import 'package:freezed_annotation/freezed_annotation.dart';

part 'space_member.freezed.dart';

/// Papel de um membro no espaço (matriz do PRD §7).
///
/// Os papéis são **por espaço**, não por usuário: a mesma pessoa pode ser
/// `admin` da república e `viewer` do household. É o que `space_members.role`
/// modela, e a razão de o papel não morar em `profiles`.
enum SpaceRole {
  /// Tudo, inclusive convidar, remover membro, trocar papel e arquivar.
  admin,

  /// Lança e edita; não mexe em quem está no espaço.
  editor,

  /// Só lê.
  viewer;

  static SpaceRole fromDb(String value) => switch (value) {
    'admin' => SpaceRole.admin,
    'editor' => SpaceRole.editor,
    'viewer' => SpaceRole.viewer,
    _ => throw ArgumentError.value(value, 'role', 'Papel inválido'),
  };

  String get db => name;

  String get label => switch (this) {
    SpaceRole.admin => 'Admin',
    SpaceRole.editor => 'Editor',
    SpaceRole.viewer => 'Leitor',
  };

  /// O que o papel permite, em uma frase — para a lista de membros dizer o que
  /// cada um pode em vez de exibir um rótulo sem significado.
  String get description => switch (this) {
    SpaceRole.admin => 'Convida, remove e edita tudo',
    SpaceRole.editor => 'Lança e edita',
    SpaceRole.viewer => 'Só vê',
  };

  /// Pode criar e editar lançamentos, orçamentos e metas (PRD §7).
  bool get canWrite => this != SpaceRole.viewer;

  /// Pode convidar, remover membro, trocar papel e arquivar o espaço.
  ///
  /// `editor` é "⚙️ configurável" na matriz do PRD para convidar. Aqui ele
  /// **não** convida: a configuração por espaço é uma tela que não existe, e o
  /// padrão restritivo é o que dá para reverter depois sem quebrar ninguém.
  bool get canManageMembers => this == SpaceRole.admin;
}

/// Situação do vínculo (PRD §12).
enum MembershipStatus {
  /// Convidado e ainda não aceitou. Não existe hoje: entrar por código já cria
  /// a linha como `active`. Fica no domínio porque a coluna aceita o valor e um
  /// convite por e-mail (Fase 3) o produziria.
  invited,

  active,

  /// Saiu ou foi removido. A linha **permanece** para o histórico não ficar
  /// órfão, e é ela que `join_space_by_code` reativa quando a pessoa volta.
  left;

  static MembershipStatus fromDb(String value) => switch (value) {
    'invited' => MembershipStatus.invited,
    'active' => MembershipStatus.active,
    'left' => MembershipStatus.left,
    _ => throw ArgumentError.value(value, 'status', 'Status inválido'),
  };

  String get db => name;
}

/// Entidade de domínio: o vínculo de um usuário com um espaço.
@freezed
abstract class SpaceMember with _$SpaceMember {
  const factory SpaceMember({
    required String id,
    required String spaceId,
    required String userId,
    required SpaceRole role,
    required MembershipStatus status,
    required DateTime joinedAt,

    /// Nome de quem é este vínculo, copiado de `profiles.display_name`.
    ///
    /// **Cópia, nunca fonte.** A UI não escreve este campo: quem o mantém são
    /// dois triggers no Postgres (ver a migration 20260801205317). Ele existe
    /// porque sync rule não faz join — sem a coluna, o nome do outro membro não
    /// chega ao aparelho.
    ///
    /// Nulo é o caso normal de quem nunca abriu o Perfil, e a lista de membros
    /// cai no texto que existia antes desta coluna.
    String? displayName,

    /// Cota padrão no rateio de despesa do grupo (RN-2.1, `percentage`).
    ///
    /// Nula é o caso normal: sem cota declarada, o rateio cai no igualitário.
    /// A coluna existe desde a fundação e só ganha uso na fatia de split.
    double? sharePercentage,
  }) = _SpaceMember;

  const SpaceMember._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  factory SpaceMember.fromRow(Map<String, Object?> row) => SpaceMember(
    id: row['id']! as String,
    spaceId: row['space_id']! as String,
    userId: row['user_id']! as String,
    role: SpaceRole.fromDb(row['role']! as String),
    status: MembershipStatus.fromDb(row['status']! as String),
    joinedAt: DateTime.parse(row['joined_at']! as String),
    displayName: row['display_name'] as String?,
    // `share_percentage` é `numeric` no Postgres e chega como texto na coluna
    // local (ver `schema.dart`): o PowerSync não tem tipo decimal, e ler como
    // número aqui é o que evita espalhar o `parse` por quem consome.
    sharePercentage: switch (row['share_percentage']) {
      final String value => double.tryParse(value),
      final num value => value.toDouble(),
      _ => null,
    },
  );

  /// Colunas para INSERT no banco local.
  Map<String, Object?> toColumns() => {
    'id': id,
    'space_id': spaceId,
    'user_id': userId,
    'role': role.db,
    'status': status.db,
    // Vai no INSERT local para a linha recém-criada já mostrar o nome sem
    // esperar o round-trip. No Postgres o trigger de `before insert` reescreve
    // o valor a partir de `profiles`, que é quem manda.
    'display_name': displayName,
    'share_percentage': sharePercentage?.toString(),
    'joined_at': joinedAt.toUtc().toIso8601String(),
    'created_at': joinedAt.toUtc().toIso8601String(),
    'updated_at': joinedAt.toUtc().toIso8601String(),
  };

  bool get isActive => status == MembershipStatus.active;
}
