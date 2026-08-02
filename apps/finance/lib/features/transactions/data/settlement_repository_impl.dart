import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/settlement.dart';
import '../domain/settlement_repository.dart';

/// O SQL do acerto, em constantes.
///
/// Pelo mesmo motivo de `ExpenseSplitSql`: é SQL **novo** sobre views com
/// triggers `INSTEAD OF`, e mock de `SqliteConnection` não distingue SQL válido
/// de SQL que o SQLite recusa. Em constante, o teste de integração roda
/// exatamente estas strings.
abstract final class SettlementSql {
  /// Os tipos que entram no saldo, como literal de SQL.
  ///
  /// `expense` é a despesa rateada. `transfer` é o **acerto**: entra pela mesma
  /// porta, e é por isso que zera o par sem lógica especial. `income` e
  /// `savings` ficam fora — receita de grupo não é dívida de ninguém, e
  /// poupança é individual por desenho.
  static const _types = "('expense', 'transfer')";

  /// Só lançamento **com partes** conta.
  ///
  /// Despesa de grupo não dividida é gasto de quem lançou; contá-la
  /// transformaria qualquer lançamento no espaço em cobrança silenciosa. E
  /// `transfer` sem partes é pagamento de fatura vindo do Open Finance, que não
  /// tem nada a ver com acerto.
  static const _hasSplits =
      'EXISTS (SELECT 1 FROM expense_splits s2 '
      'WHERE s2.transaction_id = t.id)';

  /// Saldo líquido por pessoa, e quantos lançamentos divididos o produziram.
  ///
  /// ─────────────────────────────────────────────────────────────────────────
  /// SEM CTE, DE PROPÓSITO
  ///
  /// `watch` descobre as tabelas de origem por `EXPLAIN QUERY PLAN`, e as
  /// tabelas locais do PowerSync são views. Uma tabela que a detecção não veja
  /// significa stream que **não re-emite** — tela que congela sem erro nenhum,
  /// que é o modo de falha favorito desta base. Subquery derivada mantém
  /// `transactions` e `expense_splits` visíveis no plano.
  ///
  /// `COALESCE(paid_by, created_by)` é a mesma regra do trigger do Postgres
  /// (migration 20260801224605) e de `Transaction.fromRow`: nulo significa quem
  /// lançou. Ela aparece três vezes no projeto porque a linha local não tem
  /// trigger — não é duplicação por descuido.
  static const watchBalances =
      'SELECT b.user_id AS user_id, b.currency AS currency, '
      'SUM(b.paid) AS paid_minor, SUM(b.owed) AS owed_minor, '
      '(SELECT COUNT(*) FROM transactions t '
      'WHERE t.space_id = ? AND t.type IN $_types AND $_hasSplits) '
      'AS split_count '
      'FROM (SELECT COALESCE(t.paid_by, t.created_by) AS user_id, '
      't.currency AS currency, t.amount_minor AS paid, 0 AS owed '
      'FROM transactions t '
      'WHERE t.space_id = ? AND t.type IN $_types AND $_hasSplits '
      'UNION ALL '
      'SELECT s.user_id AS user_id, s.currency AS currency, '
      '0 AS paid, s.amount_minor AS owed '
      'FROM expense_splits s JOIN transactions t ON t.id = s.transaction_id '
      'WHERE s.space_id = ? AND t.type IN $_types) b '
      'GROUP BY b.user_id, b.currency '
      'ORDER BY b.user_id';

  static const spaceTypeById = 'SELECT space_type FROM spaces WHERE id = ?';

  static const insertTransfer =
      'INSERT INTO transactions '
      '(id, space_id, account_id, created_by, paid_by, type, amount_minor, '
      'currency, category_id, description, occurred_at, source, is_shared, '
      'ai_categorized, recurrence_id, created_at, updated_at) '
      'VALUES (?, ?, NULL, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, NULL, ?, ?)';

  static const insertSplit =
      'INSERT INTO expense_splits '
      '(id, transaction_id, space_id, user_id, amount_minor, currency, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)';
}

/// Lê as linhas de [SettlementSql.watchBalances] como um [Settlement].
///
/// Público, e não método privado do repositório, pelo mesmo motivo de
/// `SettlementSql` estar em constantes: é o teste que roda o SQL de verdade que
/// precisa alcançá-lo. Se a leitura fosse privada, o teste de integração
/// remontaria a conversão à mão e um erro de nome de coluna passaria batido nas
/// duas pontas.
Settlement settlementFromRows(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return Settlement.nothingSplit;

  return Settlement.from(
    balances: [
      for (final row in rows)
        MemberBalance(
          userId: row['user_id']! as String,
          net: Money.fromMinor(
            (row['paid_minor']! as int) - (row['owed_minor']! as int),
            currency: row['currency']! as String,
          ),
        ),
    ],
    splitCount: rows.first['split_count']! as int,
  );
}

/// Implementação sobre o PowerSync (SQL bruto), como os outros repositórios.
class SettlementRepositoryImpl implements SettlementRepository {
  SettlementRepositoryImpl({
    required this.db,
    required this.supabase,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('SettlementRepository');

  final SqliteConnection db;
  final SupabaseClient supabase;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  @override
  Stream<Settlement> watch(String spaceId) => db
      .watch(
        SettlementSql.watchBalances,
        parameters: [spaceId, spaceId, spaceId],
      )
      .map(settlementFromRows);

  @override
  Future<Result<void, Failure>> settle({
    required String spaceId,
    required String fromUserId,
    required String toUserId,
    required Money amount,
    String? description,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(
        AuthFailure('Nenhuma sessão ativa para registrar o acerto.'),
      );
    }
    if (!amount.isPositive) {
      return const Err(ValidationFailure('Não há nada a acertar.'));
    }
    if (fromUserId == toUserId) {
      return const Err(
        ValidationFailure('Ninguém acerta uma dívida consigo mesmo.'),
      );
    }

    try {
      final done = await db.writeTransaction<bool>((tx) async {
        final spaceRows = await tx.getAll(SettlementSql.spaceTypeById, [
          spaceId,
        ]);
        if (spaceRows.isEmpty || spaceRows.first['space_type'] != 'group') {
          return false;
        }

        // As duas linhas na mesma transação, pelo mesmo argumento que faz
        // `is_shared` e as partes nascerem juntas: o `transfer` sozinho seria
        // um lançamento sem dono da dívida, e a parte sozinha apontaria para um
        // lançamento que não existe. Nenhum dos dois estados é legível.
        final stamp = _now().toUtc().toIso8601String();
        final transactionId = _genId();
        final minor = amount.amountMinor.abs();

        await tx.execute(SettlementSql.insertTransfer, [
          transactionId,
          spaceId,
          // Quem registra é quem está olhando; quem pagou é a ponta `from`. A
          // policy de INSERT do Postgres exige `created_by = auth.uid()`, e é
          // justamente por isso que os dois campos são separados: eu registro o
          // acerto que a outra pessoa pagou.
          userId,
          fromUserId,
          'transfer',
          minor,
          amount.currency,
          description,
          stamp,
          'manual',
          1,
          0,
          stamp,
          stamp,
        ]);

        await tx.execute(SettlementSql.insertSplit, [
          _genId(),
          transactionId,
          spaceId,
          toUserId,
          minor,
          amount.currency,
          stamp,
          stamp,
        ]);

        return true;
      });

      if (!done) {
        return const Err(
          ValidationFailure('Só um grupo tem contas a acertar.'),
        );
      }
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao registrar o acerto', e, st);
      return Err(
        DatabaseFailure('Não foi possível registrar o acerto.', cause: e),
      );
    }
  }
}
