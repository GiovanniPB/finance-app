import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/transactions/domain/expense_split.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import 'helpers/local_stack.dart';

/// A divisão de despesa contra o PowerSync de verdade.
///
/// É o degrau que justifica existir: `expense_splits` é **tabela nova**, e todo
/// o SQL da fatia (INSERT com oito colunas, DELETE por lançamento, o
/// `writeTransaction` que junta marca e partes) atravessa uma view com triggers
/// `INSTEAD OF`. Mock de `SqliteConnection` não distingue SQL que o SQLite
/// aceita de SQL que ele recusa — foi assim que o UPSERT de orçamento ficou
/// verde por meses estando quebrado.
///
/// O que **não** se prova aqui: a RLS e o trigger que herda `space_id` da
/// migration `20260801214203`, que rodam no Postgres. Nem a republicação das
/// sync rules, que é passo manual no dashboard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Um espaço `group` com [members] pessoas ativas, e o usuário da sessão
  /// (`user-1`) sempre como a primeira a entrar.
  Future<void> seedGroup(PowerSyncDatabase db, {int members = 2}) async {
    await seedSpace(db, spaceType: 'group');
    await seedSystemCategory(db);
    for (var i = 1; i <= members; i++) {
      await seedMember(
        db,
        id: 'm-$i',
        userId: 'user-$i',
        role: i == 1 ? 'admin' : 'editor',
        // Dias diferentes para a ordem de entrada ser determinística.
        joinedAt: '2026-07-0${i}T00:00:00.000Z',
      );
    }
  }

  Future<Transaction> seedExpense(
    LocalStack stack, {
    int amountMinor = 24000,
    TransactionType type = TransactionType.expense,
  }) async {
    final created = await stack.container
        .read(transactionsRepositoryProvider)
        .create(
          spaceId: 'space-1',
          type: type,
          amount: Money.fromMinor(amountMinor),
          occurredAt: DateTime.utc(2026, 7, 28),
          categoryId: 'cat-1',
          description: 'Mercado',
        );
    return created.valueOrNull!;
  }

  group('splitEqually', () {
    test(r'duas pessoas, R$ 240,00: duas partes de R$ 120,00', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      final result = await repo.splitEqually(transaction.id);

      expect(result.isOk, isTrue);
      final splits = result.valueOrNull!;
      expect(splits.map((s) => s.amount.amountMinor), [12000, 12000]);
      expect(splits.map((s) => s.userId), ['user-1', 'user-2']);
    });

    // O caso que prova a matemática: o centavo que não divide não se perde.
    test(r'três pessoas, R$ 10,00: 3,34 + 3,33 + 3,33 fecha o total', () async {
      final stack = await localStack();
      await seedGroup(stack.db, members: 3);
      final transaction = await seedExpense(stack, amountMinor: 1000);
      final repo = stack.container.read(transactionsRepositoryProvider);

      final splits = (await repo.splitEqually(transaction.id)).valueOrNull!;

      expect(splits.map((s) => s.amount.amountMinor), [334, 333, 333]);
      expect(splits.total, const Money.fromMinor(1000));
    });

    test(r'R$ 0,01 entre três grava as duas partes de zero', () async {
      final stack = await localStack();
      await seedGroup(stack.db, members: 3);
      final transaction = await seedExpense(stack, amountMinor: 1);
      final repo = stack.container.read(transactionsRepositoryProvider);

      final splits = (await repo.splitEqually(transaction.id)).valueOrNull!;

      // Omitir as duas pessoas mentiria sobre quem participou da despesa. O
      // `check` no Postgres é `>= 0` justamente por isto.
      expect(splits, hasLength(3));
      expect(splits.map((s) => s.amount.amountMinor), [1, 0, 0]);
    });

    test('marca is_shared na mesma transação em que grava as partes', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      await repo.splitEqually(transaction.id);

      final row = await stack.db.getOptional(
        'SELECT is_shared FROM transactions WHERE id = ?',
        [transaction.id],
      );
      expect(row?['is_shared'], 1);
    });

    test('membro que saiu fica fora do rateio', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      await seedMember(
        stack.db,
        id: 'm-3',
        userId: 'user-3',
        status: 'left',
        joinedAt: '2026-07-03T00:00:00.000Z',
      );
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      final splits = (await repo.splitEqually(transaction.id)).valueOrNull!;

      expect(splits, hasLength(2));
      expect(splits.map((s) => s.userId), isNot(contains('user-3')));
    });

    // O `unique (transaction_id, user_id)` é a rede; o caminho é apagar e
    // reinserir. Sem isso, o toque duplo dobraria o rateio.
    test('dividir duas vezes não duplica parte', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      await repo.splitEqually(transaction.id);
      await repo.splitEqually(transaction.id);

      final rows = await stack.db.getAll(
        'SELECT * FROM expense_splits WHERE transaction_id = ?',
        [transaction.id],
      );
      expect(rows, hasLength(2));
    });

    test('espaço personal recusa, sem gravar nada', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      await seedSystemCategory(stack.db);
      await seedMember(stack.db, id: 'm-1', userId: 'user-1', role: 'admin');
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      final result = await repo.splitEqually(transaction.id);

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(await stack.db.getAll('SELECT * FROM expense_splits'), isEmpty);
    });

    test('receita recusa, sem gravar nada', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(
        stack,
        type: TransactionType.income,
      );
      final repo = stack.container.read(transactionsRepositoryProvider);

      final result = await repo.splitEqually(transaction.id);

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(await stack.db.getAll('SELECT * FROM expense_splits'), isEmpty);
    });

    test('lançamento inexistente devolve erro em vez de gravar', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final repo = stack.container.read(transactionsRepositoryProvider);

      final result = await repo.splitEqually('nao-existe');

      expect(result.failureOrNull, isA<DatabaseFailure>());
      expect(await stack.db.getAll('SELECT * FROM expense_splits'), isEmpty);
    });
  });

  group('watchSplits', () {
    test('lançamento não dividido emite lista vazia', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      await expectLater(repo.watchSplits(transaction.id), emits(isEmpty));
    });

    test('dividir faz o watch emitir', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      // A expectativa é montada antes da escrita: é a inscrição já viva que
      // torna isto uma prova de reatividade.
      final reacted = expectLater(
        repo.watchSplits(transaction.id),
        emitsThrough(hasLength(2)),
      );

      await repo.splitEqually(transaction.id);
      await reacted;
    });
  });

  group('removeSplit', () {
    test('apaga as partes e limpa is_shared', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);
      await repo.splitEqually(transaction.id);

      final result = await repo.removeSplit(transaction.id);

      expect(result.isOk, isTrue);
      expect(await stack.db.getAll('SELECT * FROM expense_splits'), isEmpty);
      final row = await stack.db.getOptional(
        'SELECT is_shared FROM transactions WHERE id = ?',
        [transaction.id],
      );
      expect(row?['is_shared'], 0);
    });

    test('desfazer sem divisão não explode', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      expect((await repo.removeSplit(transaction.id)).isOk, isTrue);
    });
  });

  group('editar um lançamento dividido', () {
    // Sem refazer as partes, a soma deixa de fechar o total em silêncio — o
    // pior modo de falhar nesta base.
    test('trocar o valor refaz o rateio', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);
      await repo.splitEqually(transaction.id);

      final updated = await repo.update(
        transaction.copyWith(
          amount: const Money.fromMinor(-30000),
          isShared: true,
        ),
      );

      expect(updated.isOk, isTrue);
      final splits = await repo.watchSplits(transaction.id).first;
      expect(splits.map((s) => s.amount.amountMinor), [15000, 15000]);
      expect(splits.total, const Money.fromMinor(30000));
    });

    // A folha de edição carrega o lançamento como ele estava ao abrir. Dividir
    // e salvar em seguida mandaria `is_shared = 0` de volta se `update`
    // acreditasse na entidade — apagando a marca e deixando as partes órfãs,
    // sem erro nenhum.
    test('salvar depois de dividir não apaga a marca', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);
      await repo.splitEqually(transaction.id);

      // `transaction` é a entidade de ANTES da divisão: `isShared` é falso.
      final saved = await repo.update(
        transaction.copyWith(description: 'Feira'),
      );

      expect(saved.valueOrNull?.isShared, isTrue);
      final row = await stack.db.getOptional(
        'SELECT is_shared FROM transactions WHERE id = ?',
        [transaction.id],
      );
      expect(row?['is_shared'], 1);
      expect(await repo.watchSplits(transaction.id).first, hasLength(2));
    });

    test('lançamento não dividido não ganha parte ao ser editado', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);

      await repo.update(transaction.copyWith(description: 'Feira'));

      expect(await stack.db.getAll('SELECT * FROM expense_splits'), isEmpty);
    });

    test('apagar o lançamento leva as partes (cascade local)', () async {
      final stack = await localStack();
      await seedGroup(stack.db);
      final transaction = await seedExpense(stack);
      final repo = stack.container.read(transactionsRepositoryProvider);
      await repo.splitEqually(transaction.id);

      await repo.delete(transaction.id);

      // O `on delete cascade` do Postgres **não** existe no SQLite local: view
      // não tem chave estrangeira. Este teste falhou na primeira rodada e é a
      // razão de `delete` apagar as partes à mão, na mesma transação.
      final orphans = await stack.db.getAll(
        'SELECT * FROM expense_splits WHERE transaction_id = ?',
        [transaction.id],
      );
      expect(orphans, isEmpty, reason: 'partes órfãs no banco local');
    });
  });
}
