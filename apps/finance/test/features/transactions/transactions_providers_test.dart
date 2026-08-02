import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/budgets/domain/budget.dart';
import 'package:finance/features/budgets/domain/budgets_repository.dart';
import 'package:finance/features/budgets/presentation/budgets_providers.dart';
import 'package:finance/features/categories/domain/category.dart';
import 'package:finance/features/categories/presentation/categories_providers.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/presentation/spaces_providers.dart';
import 'package:finance/features/transactions/domain/expense_split.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/domain/transactions_repository.dart';
import 'package:finance/features/transactions/presentation/transactions_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Import seletivo: os outros fakes deste arquivo colidiriam com os do harness.
// Só a categoria vem de lá — era a segunda cópia do mesmo fake.
import '../../helpers/app_harness.dart'
    show FakeCategoriesRepository, FakeSpacesRepository, testNow;

// ---------------------------------------------------------------------------
// Fakes: preferidos a mocks para dependências com comportamento (ver regras).
// ---------------------------------------------------------------------------

class FakeTransactionsRepository implements TransactionsRepository {
  FakeTransactionsRepository(this._transactions);
  final List<Transaction> _transactions;

  /// Argumentos da última chamada, para verificar o escopo aplicado.
  String? lastSpaceId;
  DateTime? lastFrom;
  DateTime? lastTo;

  @override
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) {
    lastSpaceId = spaceId;
    lastFrom = from;
    lastTo = to;
    return Stream.value(_transactions);
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
  }) async => throw UnimplementedError();

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

class FakeBudgetsRepository implements BudgetsRepository {
  FakeBudgetsRepository(this._budgets);
  final List<Budget> _budgets;

  @override
  Stream<List<Budget>> watchBySpace(String spaceId) => Stream.value(_budgets);

  @override
  Future<Result<Budget, Failure>> upsert({
    required String spaceId,
    required String categoryId,
    required Money limit,
    required DateTime startsAt,
    BudgetPeriod period = BudgetPeriod.monthly,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void, Failure>> delete(String id) async =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------

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

Transaction tx({
  required int minor,
  TransactionType type = TransactionType.expense,
  String? categoryId = 'cat-1',
  String id = 'tx',
}) => Transaction(
  id: id,
  spaceId: 'space-1',
  createdBy: 'user-1',
  type: type,
  amount: Money.fromMinor(type.isOutflow ? -minor.abs() : minor.abs()),
  occurredAt: DateTime.utc(2026, 7, 15),
  source: TransactionSource.manual,
  isShared: false,
  aiCategorized: false,
  createdAt: DateTime.utc(2026, 7, 15),
  updatedAt: DateTime.utc(2026, 7, 15),
  categoryId: categoryId,
);

Category category(String id, {String name = 'Alimentação'}) => Category(
  id: id,
  name: name,
  iconKey: 'food',
  isSystem: true,
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

Budget budget({
  String id = 'bud-1',
  String categoryId = 'cat-1',
  int limitMinor = 120000,
  BudgetPeriod period = BudgetPeriod.monthly,
  DateTime? startsAt,
}) => Budget(
  id: id,
  spaceId: 'space-1',
  categoryId: categoryId,
  limit: Money.fromMinor(limitMinor),
  period: period,
  startsAt: startsAt ?? DateTime.utc(2026, 7),
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

/// Container com todos os repositórios falsos, já com o espaço sincronizado.
Future<ProviderContainer> ready({
  List<Space>? spaces,
  List<Transaction> transactions = const [],
  List<Category> categories = const [],
  List<Budget> budgets = const [],
  FakeTransactionsRepository? transactionsRepo,
}) async {
  final container = ProviderContainer(
    overrides: [
      spacesRepositoryProvider.overrideWithValue(
        FakeSpacesRepository(spaces ?? [personalSpace()]),
      ),
      transactionsRepositoryProvider.overrideWithValue(
        transactionsRepo ?? FakeTransactionsRepository(transactions),
      ),
      categoriesRepositoryProvider.overrideWithValue(
        FakeCategoriesRepository(categories),
      ),
      budgetsRepositoryProvider.overrideWithValue(
        FakeBudgetsRepository(budgets),
      ),
      // Sem isto o mês em foco nasce do relógio real, e todo helper deste
      // arquivo ancora em julho de 2026 — a suíte passava por coincidência de
      // calendário e virou vermelha sozinha em 1º de agosto.
      clockProvider.overrideWithValue(() => testNow),
    ],
  );
  addTearDown(container.dispose);

  // Sem ouvinte, um provider auto-dispose é descartado antes de emitir. Manter
  // os providers de folha escutados simula o que a árvore de widgets faria e
  // mantém vivas todas as dependências.
  addTearDown(container.listen(activeSpaceProvider, (_, _) {}).close);
  addTearDown(container.listen(monthTransactionsProvider, (_, _) {}).close);
  addTearDown(container.listen(monthSummaryProvider, (_, _) {}).close);
  addTearDown(container.listen(categoriesProvider, (_, _) {}).close);
  addTearDown(container.listen(categoriesByIdProvider, (_, _) {}).close);
  addTearDown(container.listen(budgetsProvider, (_, _) {}).close);
  addTearDown(container.listen(budgetUsageProvider, (_, _) {}).close);

  await container.read(spacesProvider.future);
  return container;
}

void main() {
  group('FocusedMonth', () {
    test('começa no mês corrente, normalizado no dia 1', () async {
      final container = await ready();
      final month = container.read(focusedMonthProvider);

      // Contra o relógio injetado, não contra `DateTime.now()`: comparar com o
      // relógio real faria este teste passar mesmo se o provider ignorasse o
      // `clockProvider` — que foi exatamente o defeito.
      expect(month.year, testNow.year);
      expect(month.month, testNow.month);
      expect(month.day, 1);
    });

    test('previous e next andam de mês', () async {
      final container = await ready();
      final notifier = container.read(focusedMonthProvider.notifier)
        ..select(DateTime.utc(2026, 7))
        ..previous();
      expect(container.read(focusedMonthProvider), DateTime(2026, 6));

      notifier
        ..next()
        ..next();
      expect(container.read(focusedMonthProvider), DateTime(2026, 8));
    });

    test('atravessa a virada de ano corretamente', () async {
      final container = await ready();
      final notifier = container.read(focusedMonthProvider.notifier)
        ..select(DateTime.utc(2026))
        ..previous();
      expect(container.read(focusedMonthProvider), DateTime(2025, 12));

      notifier
        ..select(DateTime.utc(2026, 12))
        ..next();
      expect(container.read(focusedMonthProvider), DateTime(2027));
    });

    test('select normaliza para o dia 1', () async {
      final container = await ready();

      container
          .read(focusedMonthProvider.notifier)
          .select(
            DateTime.utc(2026, 3, 19, 15, 30),
          );

      expect(container.read(focusedMonthProvider), DateTime(2026, 3));
    });
  });

  group('monthTransactions', () {
    test('sem espaço ativo devolve lista vazia', () async {
      final container = await ready(spaces: []);

      expect(await container.read(monthTransactionsProvider.future), isEmpty);
    });

    test('aplica o escopo de espaço e a janela do mês', () async {
      final repo = FakeTransactionsRepository([tx(minor: 100)]);
      final container = await ready(transactionsRepo: repo);

      container
          .read(focusedMonthProvider.notifier)
          .select(
            DateTime.utc(2026, 7),
          );
      await container.read(monthTransactionsProvider.future);

      expect(repo.lastSpaceId, 'space-1');
      expect(repo.lastFrom, DateTime(2026, 7));
      // Janela exclusiva no fim: o mês seguinte não entra.
      expect(repo.lastTo, DateTime(2026, 8));
    });

    test('a janela acompanha a troca de mês', () async {
      final repo = FakeTransactionsRepository(const []);
      final container = await ready(transactionsRepo: repo);

      container
          .read(focusedMonthProvider.notifier)
          .select(
            DateTime.utc(2026, 12),
          );
      await container.read(monthTransactionsProvider.future);

      expect(repo.lastFrom, DateTime(2026, 12));
      expect(repo.lastTo, DateTime(2027));
    });

    test('repassa as transações do repositório', () async {
      final container = await ready(
        transactions: [
          tx(minor: 100),
          tx(minor: 200, id: 'tx-2'),
        ],
      );

      expect(
        await container.read(monthTransactionsProvider.future),
        hasLength(2),
      );
    });
  });

  group('monthSummary', () {
    test('é vazio antes do primeiro emit', () async {
      final container = await ready(spaces: []);

      expect(container.read(monthSummaryProvider).outflow.isZero, isTrue);
    });

    test('agrega as transações carregadas', () async {
      final container = await ready(
        transactions: [
          tx(minor: 14280),
          tx(minor: 540000, type: TransactionType.income, id: 'tx-2'),
        ],
      );
      await container.read(monthTransactionsProvider.future);

      final summary = container.read(monthSummaryProvider);
      expect(summary.outflow.amountMinor, 14280);
      expect(summary.income.amountMinor, 540000);
      expect(summary.balance.amountMinor, 525720);
    });
  });

  group('categories', () {
    test('sem espaço ativo devolve lista vazia', () async {
      final container = await ready(spaces: []);

      expect(await container.read(categoriesProvider.future), isEmpty);
    });

    test('categoriesById indexa por id', () async {
      final container = await ready(
        categories: [
          category('cat-1'),
          category('cat-2', name: 'Transporte'),
        ],
      );
      await container.read(categoriesProvider.future);

      final index = container.read(categoriesByIdProvider);
      expect(index['cat-1']?.name, 'Alimentação');
      expect(index['cat-2']?.name, 'Transporte');
    });

    test('categoriesById é imutável', () async {
      final container = await ready(categories: [category('cat-1')]);
      await container.read(categoriesProvider.future);

      expect(
        () => container.read(categoriesByIdProvider)['x'] = category('x'),
        throwsUnsupportedError,
      );
    });

    test('categoriesById é vazio antes do sync', () async {
      final container = await ready(spaces: []);

      expect(container.read(categoriesByIdProvider), isEmpty);
    });
  });

  group('budgetUsage', () {
    test('sem espaço ativo devolve lista vazia', () async {
      final container = await ready(spaces: []);

      expect(container.read(budgetUsageProvider), isEmpty);
    });

    test('cruza orçamento com o gasto do mês', () async {
      final container = await ready(
        transactions: [tx(minor: 84210)],
        budgets: [budget()],
      );
      await container.read(monthTransactionsProvider.future);
      await container.read(budgetsProvider.future);

      final usage = container.read(budgetUsageProvider);
      expect(usage, hasLength(1));
      expect(usage.single.spent.amountMinor, 84210);
      expect(usage.single.percent, 70);
    });

    test('ordena o que precisa de atenção primeiro', () async {
      final container = await ready(
        transactions: [
          tx(minor: 10000),
          tx(minor: 29000, categoryId: 'cat-2', id: 'tx-2'),
        ],
        budgets: [
          budget(limitMinor: 100000),
          budget(id: 'bud-2', categoryId: 'cat-2', limitMinor: 30000),
        ],
      );
      await container.read(monthTransactionsProvider.future);
      await container.read(budgetsProvider.future);

      final usage = container.read(budgetUsageProvider);
      // cat-2 está em 96%; cat-1 em 10%.
      expect(usage.first.categoryId, 'cat-2');
      expect(usage.last.categoryId, 'cat-1');
    });

    test('ignora orçamento semanal na Fase 0', () async {
      final container = await ready(
        budgets: [budget(period: BudgetPeriod.weekly)],
      );
      await container.read(budgetsProvider.future);

      expect(container.read(budgetUsageProvider), isEmpty);
    });

    test('ignora orçamento que começa depois do mês em foco', () async {
      final container = await ready(
        budgets: [budget(startsAt: DateTime.utc(2026, 9))],
      );
      await container.read(budgetsProvider.future);
      container
          .read(focusedMonthProvider.notifier)
          .select(
            DateTime.utc(2026, 7),
          );

      expect(container.read(budgetUsageProvider), isEmpty);
    });

    test(
      'mantém só o orçamento vigente quando a categoria foi reorçada',
      () async {
        // Limite definido em maio e refeito em julho: em julho vale o de julho,
        // e a categoria não pode aparecer duas vezes na lista.
        final container = await ready(
          transactions: [tx(minor: 60000)],
          budgets: [
            budget(id: 'bud-maio', startsAt: DateTime.utc(2026, 5)),
            budget(
              id: 'bud-julho',
              limitMinor: 60000,
              startsAt: DateTime.utc(2026, 7),
            ),
          ],
        );
        await container.read(monthTransactionsProvider.future);
        await container.read(budgetsProvider.future);
        container
            .read(focusedMonthProvider.notifier)
            .select(
              DateTime.utc(2026, 7),
            );

        final usage = container.read(budgetUsageProvider);
        expect(usage, hasLength(1));
        expect(usage.single.budget.id, 'bud-julho');
        expect(usage.single.percent, 100);
      },
    );

    test(
      'um mês antes do reorçamento continua valendo o limite anterior',
      () async {
        final container = await ready(
          budgets: [
            budget(id: 'bud-maio', startsAt: DateTime.utc(2026, 5)),
            budget(
              id: 'bud-julho',
              limitMinor: 60000,
              startsAt: DateTime.utc(2026, 7),
            ),
          ],
        );
        await container.read(budgetsProvider.future);
        container
            .read(focusedMonthProvider.notifier)
            .select(
              DateTime.utc(2026, 6),
            );

        final usage = container.read(budgetUsageProvider);
        expect(usage, hasLength(1));
        expect(usage.single.budget.id, 'bud-maio');
      },
    );

    test('a lista devolvida é imutável', () async {
      final container = await ready(budgets: [budget()]);
      await container.read(budgetsProvider.future);

      expect(
        () => container
            .read(budgetUsageProvider)
            .add(
              BudgetUsage(budget: budget(), spent: const Money.zero()),
            ),
        throwsUnsupportedError,
      );
    });
  });
}
