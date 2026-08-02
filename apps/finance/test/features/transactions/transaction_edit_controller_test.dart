import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/transactions/domain/expense_split.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/domain/transactions_repository.dart';
import 'package:finance/features/transactions/presentation/transaction_edit_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Registra o que chegou no repositório, para verificar o que foi persistido.
class RecordingTransactionsRepository implements TransactionsRepository {
  RecordingTransactionsRepository({this.failure});

  /// Quando presente, toda escrita falha com este erro.
  final Failure? failure;

  Transaction? updated;
  final List<String> deleted = [];

  @override
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) => Stream.value(const []);

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
  }) async => throw UnimplementedError();

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async {
    updated = transaction;
    final error = failure;
    return error != null ? Err(error) : Ok(transaction);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final error = failure;
    if (error != null) return Err(error);

    deleted.add(id);
    return const Ok(null);
  }

  // A fatia `dividir-despesa` somou três métodos ao contrato. Este fake é de
  // um teste que não toca divisão, então lançar é mais honesto que devolver
  // vazio: se algum dia ele chamar, o teste diz onde.
  @override
  Stream<List<ExpenseSplit>> watchSplits(String transactionId) =>
      throw UnimplementedError();

  @override
  Future<Result<List<ExpenseSplit>, Failure>> splitEqually(
    String transactionId,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void, Failure>> removeSplit(String transactionId) async =>
      throw UnimplementedError();
}

Future<ProviderContainer> ready(RecordingTransactionsRepository repo) async {
  final container = ProviderContainer(
    overrides: [transactionsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late RecordingTransactionsRepository repo;

  setUp(() => repo = RecordingTransactionsRepository());

  TransactionEditController controller(
    ProviderContainer c,
    Transaction transaction,
  ) => c.read(transactionEditControllerProvider(transaction).notifier);

  TransactionEditState stateOf(
    ProviderContainer c,
    Transaction transaction,
  ) => c.read(transactionEditControllerProvider(transaction));

  group('estado inicial', () {
    test('nasce com os valores gravados', () async {
      final container = await ready(repo);
      // testTransaction descreve 'Mercado' por padrão.
      final tx = testTransaction(minor: 4250);

      final state = stateOf(container, tx);
      expect(state.amountMinor, 4250);
      expect(state.amountLabel, '42,50');
      expect(state.categoryId, 'cat-1');
      expect(state.description, 'Mercado');
      expect(state.type, TransactionType.expense);
      expect(state.canSave, isTrue);
    });

    test('o valor exibido é absoluto, mesmo com despesa negativa', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 4250);

      // No domínio a despesa é negativa; o campo de digitação não mostra sinal.
      expect(tx.amount.amountMinor, -4250);
      expect(stateOf(container, tx).amountMinor, 4250);
    });

    test('despesa e receita podem trocar de tipo', () async {
      final container = await ready(repo);

      expect(
        stateOf(container, testTransaction(minor: 100)).canSwitchType,
        isTrue,
      );
      expect(
        stateOf(
          container,
          testTransaction(minor: 100, type: TransactionType.income),
        ).canSwitchType,
        isTrue,
      );
    });

    test('poupança e transferência não trocam de tipo', () async {
      final container = await ready(repo);

      for (final type in [
        TransactionType.savings,
        TransactionType.transfer,
      ]) {
        final tx = testTransaction(minor: 100, type: type, id: 'tx-$type');
        expect(stateOf(container, tx).canSwitchType, isFalse);
      }
    });

    test('cada lançamento tem seu próprio estado', () async {
      final container = await ready(repo);
      final a = testTransaction(minor: 100);
      final b = testTransaction(minor: 200, id: 'tx-2');

      controller(container, a).pressDigit(5);

      expect(stateOf(container, a).amountMinor, 1005);
      expect(stateOf(container, b).amountMinor, 200);
    });
  });

  group('edição dos campos', () {
    test('apagar tudo bloqueia salvar', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 42);

      controller(container, tx)
        ..pressBackspace()
        ..pressBackspace();

      expect(stateOf(container, tx).amountMinor, 0);
      expect(stateOf(container, tx).canSave, isFalse);
    });

    test('descrição em branco volta a ser ausência de descrição', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 100);

      controller(container, tx).editDescription('   ');

      expect(stateOf(container, tx).description, isNull);
    });

    test('descrição é gravada sem espaço nas pontas', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 100);

      controller(container, tx).editDescription('  Padaria  ');

      expect(stateOf(container, tx).description, 'Padaria');
    });

    test('trocar para receita inverte o sinal do valor', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 4250);

      controller(container, tx).selectType(TransactionType.income);

      final state = stateOf(container, tx);
      expect(state.amount.amountMinor, 4250);
      expect(state.amountLabel, '42,50');
    });

    test('desmarcar a categoria deixa o lançamento sem categoria', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 100);

      controller(container, tx).selectCategory(null);

      expect(stateOf(container, tx).categoryId, isNull);
    });
  });

  group('save', () {
    test('persiste valor, tipo, categoria, data e descrição', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 4250);
      controller(container, tx)
        ..pressDigit(0)
        ..selectType(TransactionType.income)
        ..selectCategory('cat-7')
        ..selectDate(DateTime(2026, 7, 3))
        ..editDescription('Reembolso');

      final saved = await controller(container, tx).save();

      expect(saved, isTrue);
      expect(repo.updated?.id, tx.id);
      // 4250 com um zero à direita = 42.500 centavos, positivo por ser receita.
      expect(repo.updated?.amount.amountMinor, 42500);
      expect(repo.updated?.type, TransactionType.income);
      expect(repo.updated?.categoryId, 'cat-7');
      expect(repo.updated?.occurredAt, DateTime(2026, 7, 3));
      expect(repo.updated?.description, 'Reembolso');
    });

    test('despesa é persistida com sinal negativo no domínio', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 4250);

      await controller(container, tx).save();

      expect(repo.updated?.amount.amountMinor, -4250);
    });

    test('remover a categoria é persistido como ausência', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 100);
      controller(container, tx).selectCategory(null);

      await controller(container, tx).save();

      expect(repo.updated?.categoryId, isNull);
    });

    test('valor zerado recusa e explica', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 5);
      controller(container, tx).pressBackspace();

      final saved = await controller(container, tx).save();

      expect(saved, isFalse);
      expect(
        stateOf(container, tx).errorMessage,
        'Informe um valor maior que zero.',
      );
      expect(repo.updated, isNull);
    });

    test('falha do repositório vira mensagem e libera o botão', () async {
      final falha = RecordingTransactionsRepository(
        failure: const DatabaseFailure('Não foi possível salvar a transação.'),
      );
      final container = await ready(falha);
      final tx = testTransaction(minor: 100);

      final saved = await controller(container, tx).save();

      expect(saved, isFalse);
      expect(
        stateOf(container, tx).errorMessage,
        'Não foi possível salvar a transação.',
      );
      expect(stateOf(container, tx).isSaving, isFalse);
    });

    test('digitar depois do erro limpa a mensagem', () async {
      final falha = RecordingTransactionsRepository(
        failure: const DatabaseFailure('Não foi possível salvar a transação.'),
      );
      final container = await ready(falha);
      final tx = testTransaction(minor: 100);
      await controller(container, tx).save();

      controller(container, tx).pressDigit(1);

      expect(stateOf(container, tx).errorMessage, isNull);
    });
  });

  group('remove', () {
    test('exclui pelo id do lançamento', () async {
      final container = await ready(repo);
      final tx = testTransaction(minor: 100, id: 'tx-42');

      final removed = await controller(container, tx).remove();

      expect(removed, isTrue);
      expect(repo.deleted, ['tx-42']);
    });

    test('falha do repositório vira mensagem', () async {
      final falha = RecordingTransactionsRepository(
        failure: const DatabaseFailure('Não foi possível remover a transação.'),
      );
      final container = await ready(falha);
      final tx = testTransaction(minor: 100);

      final removed = await controller(container, tx).remove();

      expect(removed, isFalse);
      expect(
        stateOf(container, tx).errorMessage,
        'Não foi possível remover a transação.',
      );
    });
  });
}
