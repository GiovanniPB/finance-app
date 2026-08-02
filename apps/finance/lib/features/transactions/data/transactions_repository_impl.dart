import 'package:core/core.dart';
import 'package:powersync/powersync.dart' show uuid;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/expense_split.dart';
import '../domain/transaction.dart';
import '../domain/transactions_repository.dart';

/// O SQL da divisão, em constantes.
///
/// Separado do resto do arquivo (que usa SQL inline) porque é SQL **novo**
/// sobre uma view com triggers `INSTEAD OF`: a armadilha do `AGENTS.md` diz
/// que mock de `SqliteConnection` não distingue SQL válido de SQL que o SQLite
/// recusa. Em constante, o teste de integração roda exatamente estas strings.
abstract final class ExpenseSplitSql {
  static const columns =
      'id, transaction_id, space_id, user_id, amount_minor, currency, '
      'created_at, updated_at';

  static const watchByTransaction =
      'SELECT * FROM expense_splits WHERE transaction_id = ? '
      'ORDER BY created_at, user_id';

  static const insert =
      'INSERT INTO expense_splits ($columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?)';

  static const deleteByTransaction =
      'DELETE FROM expense_splits WHERE transaction_id = ?';

  /// Existe parte para este lançamento? É o que `update` lê para derivar
  /// `is_shared` em vez de acreditar na entidade que veio da tela.
  static const byTransaction =
      'SELECT id FROM expense_splits WHERE transaction_id = ? LIMIT 1';

  /// Membros ativos, na ordem em que entraram — é a ordem que a tela mostra.
  static const activeMembers =
      'SELECT user_id FROM space_members WHERE space_id = ? '
      "AND status = 'active' ORDER BY joined_at, user_id";

  static const transactionById =
      'SELECT * FROM transactions WHERE id = ? LIMIT 1';

  static const spaceTypeById = 'SELECT space_type FROM spaces WHERE id = ?';

  static const markShared =
      'UPDATE transactions SET is_shared = ?, updated_at = ? WHERE id = ?';

  static List<Object?> insertParams(Map<String, Object?> cols) => [
    cols['id'],
    cols['transaction_id'],
    cols['space_id'],
    cols['user_id'],
    cols['amount_minor'],
    cols['currency'],
    cols['created_at'],
    cols['updated_at'],
  ];
}

/// Implementação sobre o PowerSync (SQL bruto). Leituras via `watch`
/// (reativas), escritas via `execute` (persistem local e entram na fila de
/// upload). Depende de [SqliteConnection] para permitir teste com mocks.
class TransactionsRepositoryImpl implements TransactionsRepository {
  TransactionsRepositoryImpl({
    required this.db,
    required this.supabase,
    DateTime Function()? now,
    String Function()? genId,
    AppLogger? logger,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _genId = genId ?? uuid.v4,
       _log = logger ?? AppLogger('TransactionsRepository');

  final SqliteConnection db;
  final SupabaseClient supabase;
  final DateTime Function() _now;
  final String Function() _genId;
  final AppLogger _log;

  static const _columns =
      'id, space_id, account_id, created_by, paid_by, type, amount_minor, '
      'currency, category_id, description, occurred_at, source, is_shared, '
      'ai_categorized, recurrence_id, created_at, updated_at';

  @override
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) {
    final where = StringBuffer('space_id = ?');
    final params = <Object?>[spaceId];
    // `datetime()` nos **dois** lados, e não comparação de texto crua.
    //
    // ─────────────────────────────────────────────────────────────────────
    // MEDIDO NO SQLITE DO APP, não deduzido (2026-07-28)
    //
    // O PowerSync guarda o timestamp como `2026-07-14 02:52:38.001Z` — com
    // **espaço**. `toIso8601String()` produz `2026-07-01T00:00:00.000Z` — com
    // **T**. Em comparação de texto, `' '` (0x20) < `'T'` (0x54), então toda
    // linha do **dia 1º** do mês reprovava no `>=` e desaparecia do mês; e
    // linha do dia 1º do mês seguinte passava no `<` e entrava por engano.
    //
    // O efeito medido em julho/2026, com extrato de banco real: 8 linhas
    // sumidas e **R$ 15.111,01 de despesa invisível** no resumo do mês. Ficou
    // escondido desde a fatia de transações porque, com 8 lançamentos
    // digitados à mão, nenhum caía num dia 1º.
    //
    // `datetime()` normaliza os dois formatos ao mesmo texto, então a
    // comparação passa a valer independentemente de quem escreveu a linha —
    // cliente (com `T`) ou sincronização (com espaço). O custo é não usar
    // índice em `occurred_at`; num SQLite local de milhares de linhas isso não
    // se mede, e correção vale mais que plano de consulta.
    if (from != null) {
      where.write(' AND datetime(occurred_at) >= datetime(?)');
      params.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND datetime(occurred_at) < datetime(?)');
      params.add(to.toUtc().toIso8601String());
    }

    return db
        .watch(
          'SELECT * FROM transactions WHERE $where '
          'ORDER BY occurred_at DESC, created_at DESC',
          parameters: params,
        )
        .map((results) => results.map(Transaction.fromRow).toList());
  }

  @override
  Future<Result<Transaction, Failure>> create({
    required String spaceId,
    required TransactionType type,
    required Money amount,
    required DateTime occurredAt,
    String? accountId,
    String? categoryId,
    String? description,
    bool isShared = false,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return const Err(
        AuthFailure('Nenhuma sessão ativa para registrar transação.'),
      );
    }
    if (amount.isZero) {
      return const Err(
        ValidationFailure('Informe um valor maior que zero.'),
      );
    }

    // O domínio guarda sinal; o tipo é a fonte de verdade da direção.
    final signed = type.isOutflow ? -amount.abs : amount.abs;
    final timestamp = _now();
    final transaction = Transaction(
      id: _genId(),
      spaceId: spaceId,
      createdBy: userId,
      // Quem lança paga, até alguém dizer o contrário na folha de edição — o
      // único lugar que escreve `paid_by`. O `+` não ganha passo (ver
      // `docs/surfaces.md`).
      paidBy: userId,
      type: type,
      amount: signed,
      occurredAt: occurredAt,
      source: TransactionSource.manual,
      isShared: isShared,
      aiCategorized: false,
      createdAt: timestamp,
      updatedAt: timestamp,
      accountId: accountId,
      categoryId: categoryId,
      description: description,
    );

    try {
      final cols = transaction.toColumns();
      await db.execute(
        'INSERT INTO transactions ($_columns) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          cols['id'],
          cols['space_id'],
          cols['account_id'],
          cols['created_by'],
          cols['paid_by'],
          cols['type'],
          cols['amount_minor'],
          cols['currency'],
          cols['category_id'],
          cols['description'],
          cols['occurred_at'],
          cols['source'],
          cols['is_shared'],
          cols['ai_categorized'],
          cols['recurrence_id'],
          cols['created_at'],
          cols['updated_at'],
        ],
      );
      return Ok(transaction);
    } on Exception catch (e, st) {
      _log.severe('Falha ao criar transação', e, st);
      return Err(
        DatabaseFailure('Não foi possível registrar a transação.', cause: e),
      );
    }
  }

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async {
    var updated = transaction.copyWith(updatedAt: _now());
    try {
      // Uma transação só, porque um lançamento dividido tem as partes refeitas
      // aqui dentro. Editar o valor sem refazer o rateio faria a soma das
      // partes deixar de fechar o total — em silêncio, que é o pior modo de
      // falhar nesta base.
      // `<void>` explícito: um corpo `async {}` sem `return` tem tipo estático
      // `Future<Null>`, e sem o argumento de tipo o Dart infere `T = Null` —
      // funciona, mas quebra qualquer mock que espere `writeTransaction<void>`.
      // A mesma nota está em `savings_repository_impl.dart`.
      await db.writeTransaction<void>((tx) async {
        // ───────────────────────────────────────────────────────────────────
        // `is_shared` NÃO VEM DA ENTIDADE, VEM DA TABELA DE PARTES.
        //
        // A marca é derivada: ela significa "este lançamento tem partes", e
        // quem a move é `splitEqually`/`removeSplit`. A folha de edição carrega
        // o lançamento como ele estava **ao abrir**, então dividir e salvar em
        // seguida mandaria `is_shared = 0` de volta — apagando a marca e
        // deixando as partes órfãs, sem erro nenhum. Ler aqui dentro fecha a
        // janela, e de quebra torna impossível um chamador desalinhar os dois.
        final splits = await tx.getAll(ExpenseSplitSql.byTransaction, [
          updated.id,
        ]);
        updated = updated.copyWith(isShared: splits.isNotEmpty);
        final cols = updated.toColumns();

        await tx.execute(
          'UPDATE transactions SET type = ?, amount_minor = ?, currency = ?, '
          'category_id = ?, description = ?, occurred_at = ?, account_id = ?, '
          'paid_by = ?, is_shared = ?, updated_at = ? WHERE id = ?',
          [
            cols['type'],
            cols['amount_minor'],
            cols['currency'],
            cols['category_id'],
            cols['description'],
            cols['occurred_at'],
            cols['account_id'],
            // A folha de edição é o único lugar que escreve o pagador, e ela o
            // manda junto do resto — trocar o pagador e salvar é **uma**
            // escrita, não duas. Ver o cabeçalho de `is_shared` acima: foi por
            // separar leitura e escrita que a marca de divisão se apagava.
            cols['paid_by'],
            cols['is_shared'],
            cols['updated_at'],
            updated.id,
          ],
        );

        if (updated.isShared) {
          await _rewriteSplits(tx, updated);
        }
      });
      return Ok(updated);
    } on Exception catch (e, st) {
      _log.severe('Falha ao atualizar transação', e, st);
      return Err(
        DatabaseFailure('Não foi possível salvar a transação.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      // As partes são apagadas **à mão**, e não pelo `on delete cascade`.
      //
      // ─────────────────────────────────────────────────────────────────────
      // MEDIDO NO POWERSYNC LOCAL, não deduzido (2026-08-01)
      //
      // `expense_splits.transaction_id` tem `on delete cascade` no Postgres,
      // mas as tabelas locais do PowerSync são **views** — e view não tem
      // chave estrangeira. Apagar só o lançamento deixava as partes órfãs no
      // aparelho, o que o teste de integração desta fatia pegou na primeira
      // rodada.
      //
      // O estrago era limitado (nada lê as partes de um lançamento que não
      // existe mais) e temporário (o cascade do servidor volta pela
      // sincronização e limpa). Mas "temporário" aqui significa "quando houver
      // rede", e num app offline-first isso pode ser semanas de lixo cujo
      // tamanho cresce com o uso.
      await db.writeTransaction<void>((tx) async {
        await tx.execute(ExpenseSplitSql.deleteByTransaction, [id]);
        await tx.execute('DELETE FROM transactions WHERE id = ?', [id]);
      });
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao remover transação', e, st);
      return Err(
        DatabaseFailure('Não foi possível remover a transação.', cause: e),
      );
    }
  }

  // -----------------------------------------------------------------------
  // Divisão de despesa (RN-2.1)
  // -----------------------------------------------------------------------

  @override
  Stream<List<ExpenseSplit>> watchSplits(String transactionId) => db
      .watch(ExpenseSplitSql.watchByTransaction, parameters: [transactionId])
      .map((results) => results.map(ExpenseSplit.fromRow).toList());

  @override
  Future<Result<List<ExpenseSplit>, Failure>> splitEqually(
    String transactionId,
  ) async {
    try {
      // Tudo dentro de uma `writeTransaction`: as leituras que decidem o rateio
      // (quem é membro, quanto é o total) e as escritas que o gravam. Ler
      // fora e escrever dentro deixaria a janela em que alguém sai do espaço
      // entre a leitura e a gravação, e o rateio sairia para quem não está
      // mais lá.
      final splits = await db.writeTransaction<List<ExpenseSplit>?>((
        tx,
      ) async {
        final rows = await tx.getAll(ExpenseSplitSql.transactionById, [
          transactionId,
        ]);
        if (rows.isEmpty) return null;

        final transaction = Transaction.fromRow(rows.first);
        if (transaction.type != TransactionType.expense) {
          return const <ExpenseSplit>[];
        }

        final spaceRows = await tx.getAll(ExpenseSplitSql.spaceTypeById, [
          transaction.spaceId,
        ]);
        if (spaceRows.isEmpty) return null;
        if (spaceRows.first['space_type'] != 'group') {
          return const <ExpenseSplit>[];
        }

        final written = await _rewriteSplits(tx, transaction);
        if (written.isEmpty) return const <ExpenseSplit>[];

        await tx.execute(ExpenseSplitSql.markShared, [
          1,
          _now().toUtc().toIso8601String(),
          transactionId,
        ]);
        return written;
      });

      if (splits == null) {
        return const Err(DatabaseFailure('Este lançamento não existe mais.'));
      }
      if (splits.isEmpty) {
        // Uma só frase para os três casos, porque a UI nunca oferece o controle
        // em nenhum deles: chegar aqui é defeito de quem chamou, não do
        // usuário.
        return const Err(
          ValidationFailure('Só despesa de um grupo pode ser dividida.'),
        );
      }
      return Ok(splits);
    } on Exception catch (e, st) {
      _log.severe('Falha ao dividir a despesa', e, st);
      return Err(
        DatabaseFailure('Não foi possível dividir a despesa.', cause: e),
      );
    }
  }

  @override
  Future<Result<void, Failure>> removeSplit(String transactionId) async {
    try {
      await db.writeTransaction<void>((tx) async {
        await tx.execute(ExpenseSplitSql.deleteByTransaction, [transactionId]);
        await tx.execute(ExpenseSplitSql.markShared, [
          0,
          _now().toUtc().toIso8601String(),
          transactionId,
        ]);
      });
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao desfazer a divisão', e, st);
      return Err(
        DatabaseFailure('Não foi possível desfazer a divisão.', cause: e),
      );
    }
  }

  /// Apaga as partes que existirem e grava o rateio igual atual.
  ///
  /// Apagar-e-reinserir em vez de conciliar: o `unique (transaction_id,
  /// user_id)` recusaria o INSERT de quem já tem parte, e as tabelas locais do
  /// PowerSync são views que **recusam `UPSERT`**. Refazer também é o que torna
  /// o método idempotente — tocar duas vezes em "Dividir igualmente" dá o mesmo
  /// resultado que tocar uma.
  ///
  /// Devolve lista vazia quando o espaço não tem membro ativo nenhum, e nesse
  /// caso não escreve nada.
  Future<List<ExpenseSplit>> _rewriteSplits(
    SqliteWriteContext tx,
    Transaction transaction,
  ) async {
    final memberRows = await tx.getAll(ExpenseSplitSql.activeMembers, [
      transaction.spaceId,
    ]);
    final userIds = [for (final row in memberRows) row['user_id']! as String];
    if (userIds.isEmpty) return const [];

    await tx.execute(ExpenseSplitSql.deleteByTransaction, [transaction.id]);

    // `Money.split` usa o método do maior resto: a soma das partes é **sempre**
    // igual ao total, e o centavo que não divide vai para a primeira parte.
    final shares = transaction.amount.abs.split(userIds.length);
    final timestamp = _now();
    final splits = [
      for (var i = 0; i < userIds.length; i++)
        ExpenseSplit(
          id: _genId(),
          transactionId: transaction.id,
          spaceId: transaction.spaceId,
          userId: userIds[i],
          amount: shares[i],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
    ];

    for (final split in splits) {
      await tx.execute(
        ExpenseSplitSql.insert,
        ExpenseSplitSql.insertParams(split.toColumns()),
      );
    }
    return splits;
  }
}
