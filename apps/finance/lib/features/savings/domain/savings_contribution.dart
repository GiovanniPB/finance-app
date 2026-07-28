import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'savings_contribution.freezed.dart';

/// Como a contribuição chegou ao app (PRD RN-3.2).
enum ContributionSource {
  /// Transferência para conta marcada como alvo de poupança, detectada pela
  /// ingestão do Open Finance. Chega **não confirmada**: pode ser um movimento
  /// entre contas próprias que não é poupança (questão aberta #5 do PRD).
  openFinance,

  /// "Guardei R$ X", digitado pelo usuário. Já nasce confirmado — quem digitou
  /// o valor confirmou junto.
  manual;

  static ContributionSource fromDb(String value) => switch (value) {
    'open_finance' => ContributionSource.openFinance,
    'manual' => ContributionSource.manual,
    _ => throw ArgumentError.value(value, 'detected_via', 'Origem inválida'),
  };

  String get db =>
      this == ContributionSource.openFinance ? 'open_finance' : 'manual';
}

/// Entidade de domínio: um aporte para uma meta de poupança.
///
/// Sempre **positivo**. Retirar da poupança não é contribuição negativa — é
/// outro evento, com outra semântica de streak (RN-3.4), e será uma linha com
/// tipo próprio quando existir.
///
/// Só contribuição com [isConfirmed] entra no progresso (RN-3.3). Isso é o que
/// permite a ingestão do Open Finance propor sem alterar o número que o usuário
/// vê: o aporte aparece na lista como pendente e só passa a contar quando ele
/// diz sim.
@freezed
abstract class SavingsContribution with _$SavingsContribution {
  const factory SavingsContribution({
    required String id,
    required String goalId,
    required String spaceId,
    required String createdBy,
    required Money amount,
    required ContributionSource source,
    required bool isConfirmed,
    required DateTime contributedAt,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// Lançamento `savings` que produziu esta contribuição — a outra face do
    /// mesmo evento (ver a migration 20260728000822).
    ///
    /// Nulo é legítimo: é dinheiro que a meta conta e o extrato não explica.
    /// Acontece com toda linha gravada antes daquela migration, e vai acontecer
    /// com a detecção do Open Finance enquanto ela não tiver um lançamento
    /// nosso para apontar.
    String? transactionId,
  }) = _SavingsContribution;

  const SavingsContribution._();

  /// Constrói a partir de uma linha do SQLite local (PowerSync).
  factory SavingsContribution.fromRow(Map<String, Object?> row) =>
      SavingsContribution(
        id: row['id']! as String,
        goalId: row['goal_id']! as String,
        spaceId: row['space_id']! as String,
        createdBy: row['created_by']! as String,
        amount: Money.fromMinor(
          row['amount_minor']! as int,
          currency: row['currency'] as String? ?? Money.brl,
        ),
        source: ContributionSource.fromDb(
          row['detected_via'] as String? ?? 'manual',
        ),
        // O PowerSync materializa boolean como inteiro no SQLite local.
        isConfirmed: (row['confirmed'] as int? ?? 1) != 0,
        contributedAt: DateTime.parse(row['contributed_at']! as String),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        transactionId: row['transaction_id'] as String?,
      );

  /// Colunas para INSERT/UPDATE no banco local.
  ///
  /// Descarta o sinal: a coluna é positiva por constraint.
  ///
  /// `space_id` vai no payload porque o SQLite local não tem o trigger que o
  /// Postgres tem — o valor precisa estar certo já na escrita local, senão a
  /// linha some da UI até o sync devolver a versão corrigida.
  Map<String, Object?> toColumns() => {
    'id': id,
    'goal_id': goalId,
    'space_id': spaceId,
    'created_by': createdBy,
    'amount_minor': amount.amountMinor.abs(),
    'currency': amount.currency,
    'detected_via': source.db,
    'confirmed': isConfirmed ? 1 : 0,
    'contributed_at': contributedAt.toUtc().toIso8601String(),
    'transaction_id': transactionId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// Detectada por terceiro e ainda esperando o sim do usuário.
  bool get isPending => !isConfirmed;

  /// Se há um lançamento explicando de onde este dinheiro saiu.
  ///
  /// Falso é o caso a tratar com cuidado: excluir a contribuição não tem
  /// lançamento para levar junto, e a tela não deve prometer que tem.
  bool get hasTransaction => transactionId != null;
}
