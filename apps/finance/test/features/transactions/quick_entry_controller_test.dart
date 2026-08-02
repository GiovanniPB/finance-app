import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/presentation/spaces_providers.dart';
import 'package:finance/features/transactions/domain/expense_split.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/domain/transactions_repository.dart';
import 'package:finance/features/transactions/presentation/quick_entry_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/app_harness.dart' show FakeSpacesRepository;

/// Registra as chamadas de `create` e devolve o resultado configurado.
class RecordingTransactionsRepository implements TransactionsRepository {
  RecordingTransactionsRepository({this.failure});

  final Failure? failure;
  int createCalls = 0;
  TransactionType? lastType;
  Money? lastAmount;
  String? lastCategoryId;
  String? lastSpaceId;
  DateTime? lastOccurredAt;

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
  }) async {
    createCalls++;
    lastSpaceId = spaceId;
    lastType = type;
    lastAmount = amount;
    lastCategoryId = categoryId;
    lastOccurredAt = occurredAt;

    final error = failure;
    if (error != null) return Err(error);

    return Ok(
      Transaction(
        id: 'tx-1',
        spaceId: spaceId,
        createdBy: 'user-1',
        type: type,
        amount: amount,
        occurredAt: occurredAt,
        source: TransactionSource.manual,
        isShared: isShared,
        aiCategorized: false,
        createdAt: occurredAt,
        updatedAt: occurredAt,
        categoryId: categoryId,
      ),
    );
  }

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async =>
      throw UnimplementedError();

  @override
  Future<Result<void, Failure>> delete(String id) async =>
      throw UnimplementedError();

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

Space personalSpace() => Space(
  id: 'space-1',
  type: SpaceType.personal,
  name: 'Pessoal',
  ownerId: 'user-1',
  privacy: SpacePrivacy.sharedOnly,
  status: SpaceStatus.active,
  settlementCurrency: 'BRL',
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

Future<ProviderContainer> ready({
  List<Space>? spaces,
  RecordingTransactionsRepository? repo,
}) async {
  final container = ProviderContainer(
    overrides: [
      spacesRepositoryProvider.overrideWithValue(
        FakeSpacesRepository(spaces ?? [personalSpace()]),
      ),
      transactionsRepositoryProvider.overrideWithValue(
        repo ?? RecordingTransactionsRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(container.listen(activeSpaceProvider, (_, _) {}).close);
  addTearDown(
    container.listen(quickEntryControllerProvider, (_, _) {}).close,
  );
  await container.read(spacesProvider.future);
  return container;
}

void main() {
  group('QuickEntryController — acumulador de centavos', () {
    test('começa em zero', () async {
      final container = await ready();

      expect(container.read(quickEntryControllerProvider).amountMinor, 0);
      expect(container.read(quickEntryControllerProvider).amountLabel, '0,00');
    });

    test('cada dígito entra pela direita', () async {
      final container = await ready();
      final controller = container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(1);
      expect(container.read(quickEntryControllerProvider).amountLabel, '0,01');

      controller.pressDigit(4);
      expect(container.read(quickEntryControllerProvider).amountLabel, '0,14');

      controller.pressDigit(2);
      expect(container.read(quickEntryControllerProvider).amountLabel, '1,42');

      controller
        ..pressDigit(8)
        ..pressDigit(0);
      expect(
        container.read(quickEntryControllerProvider).amountLabel,
        '142,80',
      );
    });

    test('agrupa milhar na formatação', () async {
      final container = await ready();
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(1)
        ..pressDigit(2)
        ..pressDigit(3)
        ..pressDigit(4)
        ..pressDigit(5)
        ..pressDigit(6);

      expect(
        container.read(quickEntryControllerProvider).amountLabel,
        '1.234,56',
      );
    });

    test('backspace remove o último dígito', () async {
      final container = await ready();
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(1)
        ..pressDigit(4)
        ..pressDigit(2);

      container.read(quickEntryControllerProvider.notifier).pressBackspace();

      expect(container.read(quickEntryControllerProvider).amountLabel, '0,14');
    });

    test('backspace no zero não quebra', () async {
      final container = await ready();

      container.read(quickEntryControllerProvider.notifier).pressBackspace();

      expect(container.read(quickEntryControllerProvider).amountMinor, 0);
    });

    test('para de aceitar dígito no limite de 10 casas', () async {
      final container = await ready();
      final controller = container.read(
        quickEntryControllerProvider.notifier,
      );

      for (var i = 0; i < 15; i++) {
        controller.pressDigit(9);
      }

      final amount = container.read(quickEntryControllerProvider).amountMinor;
      expect(amount.toString().length, 10);
    });

    test('amount é sempre positivo — o tipo carrega a direção', () async {
      final container = await ready();
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(5)
        ..selectType(TransactionType.expense);

      expect(
        container.read(quickEntryControllerProvider).amount.isPositive,
        isTrue,
      );
    });
  });

  group('QuickEntryController — canSave', () {
    test('exige valor e categoria', () async {
      final container = await ready();
      final controller = container.read(
        quickEntryControllerProvider.notifier,
      );

      expect(container.read(quickEntryControllerProvider).canSave, isFalse);

      controller.pressDigit(5);
      expect(
        container.read(quickEntryControllerProvider).canSave,
        isFalse,
        reason: 'valor sem categoria não salva',
      );

      controller.selectCategory('cat-1');
      expect(container.read(quickEntryControllerProvider).canSave, isTrue);
    });

    test('categoria sem valor não habilita', () async {
      final container = await ready();

      container
          .read(quickEntryControllerProvider.notifier)
          .selectCategory('cat-1');

      expect(container.read(quickEntryControllerProvider).canSave, isFalse);
    });

    test('desmarcar a categoria desabilita de novo', () async {
      final container = await ready();
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(5)
        ..selectCategory('cat-1')
        ..selectCategory(null);

      expect(container.read(quickEntryControllerProvider).canSave, isFalse);
    });
  });

  group('QuickEntryController — seleções', () {
    test('alterna o tipo', () async {
      final container = await ready();
      final controller = container.read(
        quickEntryControllerProvider.notifier,
      );

      expect(
        container.read(quickEntryControllerProvider).type,
        TransactionType.expense,
      );

      controller.selectType(TransactionType.income);
      expect(
        container.read(quickEntryControllerProvider).type,
        TransactionType.income,
      );
    });

    test('guarda data e conta escolhidas', () async {
      final container = await ready();
      container.read(quickEntryControllerProvider.notifier)
        ..selectDate(DateTime.utc(2026, 7, 20))
        ..selectAccount('acc-1');

      final state = container.read(quickEntryControllerProvider);
      expect(state.occurredAt, DateTime.utc(2026, 7, 20));
      expect(state.accountId, 'acc-1');
    });
  });

  group('QuickEntryController — save', () {
    test('persiste com o espaço ativo e devolve true', () async {
      final repo = RecordingTransactionsRepository();
      final container = await ready(repo: repo);
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(1)
        ..pressDigit(4)
        ..pressDigit(2)
        ..pressDigit(8)
        ..pressDigit(0)
        ..selectCategory('cat-1');

      final saved = await container
          .read(quickEntryControllerProvider.notifier)
          .save();

      expect(saved, isTrue);
      expect(repo.createCalls, 1);
      expect(repo.lastSpaceId, 'space-1');
      expect(repo.lastAmount?.amountMinor, 14280);
      expect(repo.lastType, TransactionType.expense);
      expect(repo.lastCategoryId, 'cat-1');
    });

    test('data em branco vira agora', () async {
      final repo = RecordingTransactionsRepository();
      final container = await ready(repo: repo);
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(5)
        ..selectCategory('cat-1');

      await container.read(quickEntryControllerProvider.notifier).save();

      expect(repo.lastOccurredAt, isNotNull);
    });

    test('respeita a data escolhida', () async {
      final repo = RecordingTransactionsRepository();
      final container = await ready(repo: repo);
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(5)
        ..selectCategory('cat-1')
        ..selectDate(DateTime.utc(2026, 7, 20));

      await container.read(quickEntryControllerProvider.notifier).save();

      expect(repo.lastOccurredAt, DateTime.utc(2026, 7, 20));
    });

    test('sem valor devolve false e explica', () async {
      final repo = RecordingTransactionsRepository();
      final container = await ready(repo: repo);

      final saved = await container
          .read(quickEntryControllerProvider.notifier)
          .save();

      expect(saved, isFalse);
      expect(repo.createCalls, 0);
      expect(
        container.read(quickEntryControllerProvider).errorMessage,
        'Informe um valor maior que zero.',
      );
    });

    test('sem categoria devolve false e explica', () async {
      final repo = RecordingTransactionsRepository();
      final container = await ready(repo: repo);
      container.read(quickEntryControllerProvider.notifier).pressDigit(5);

      final saved = await container
          .read(quickEntryControllerProvider.notifier)
          .save();

      expect(saved, isFalse);
      expect(repo.createCalls, 0);
      expect(
        container.read(quickEntryControllerProvider).errorMessage,
        'Escolha uma categoria.',
      );
    });

    test('sem espaço sincronizado devolve false', () async {
      final repo = RecordingTransactionsRepository();
      final container = await ready(spaces: [], repo: repo);
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(5)
        ..selectCategory('cat-1');

      final saved = await container
          .read(quickEntryControllerProvider.notifier)
          .save();

      expect(saved, isFalse);
      expect(repo.createCalls, 0);
      expect(
        container.read(quickEntryControllerProvider).errorMessage,
        contains('sincronização'),
      );
    });

    test('falha do repositório vira mensagem e libera o botão', () async {
      final repo = RecordingTransactionsRepository(
        failure: const DatabaseFailure('Não foi possível registrar.'),
      );
      final container = await ready(repo: repo);
      container.read(quickEntryControllerProvider.notifier)
        ..pressDigit(5)
        ..selectCategory('cat-1');

      final saved = await container
          .read(quickEntryControllerProvider.notifier)
          .save();

      final state = container.read(quickEntryControllerProvider);
      expect(saved, isFalse);
      expect(state.errorMessage, 'Não foi possível registrar.');
      // isSaving volta a false para o usuário poder tentar de novo.
      expect(state.isSaving, isFalse);
      expect(state.canSave, isTrue);
    });

    test('digitar limpa a mensagem de erro anterior', () async {
      final container = await ready();
      await container.read(quickEntryControllerProvider.notifier).save();
      expect(
        container.read(quickEntryControllerProvider).errorMessage,
        isNotNull,
      );

      container.read(quickEntryControllerProvider.notifier).pressDigit(1);

      expect(
        container.read(quickEntryControllerProvider).errorMessage,
        isNull,
      );
    });
  });
}
