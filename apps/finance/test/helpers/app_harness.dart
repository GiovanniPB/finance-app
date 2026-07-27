import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/budgets/domain/budget.dart';
import 'package:finance/features/budgets/domain/budgets_repository.dart';
import 'package:finance/features/categories/domain/categories_repository.dart';
import 'package:finance/features/categories/domain/category.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/spaces_repository.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/domain/transactions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fakes e monta-tela compartilhados pelos testes de widget das telas.
///
/// Fakes em vez de mocks: as telas dependem de streams com comportamento, e um
/// fake explícito deixa o teste legível sem pilha de `when(...)`.

class FakeSpacesRepository implements SpacesRepository {
  FakeSpacesRepository(this.spaces);
  final List<Space> spaces;

  @override
  Stream<List<Space>> watchAll() => Stream.value(spaces);

  @override
  Stream<Space?> watchById(String id) =>
      Stream.value(spaces.where((s) => s.id == id).firstOrNull);
}

class FakeCategoriesRepository implements CategoriesRepository {
  FakeCategoriesRepository(this.categories);
  final List<Category> categories;

  @override
  Stream<List<Category>> watchForSpace(String spaceId) =>
      Stream.value(categories);

  @override
  Future<Result<Category, Failure>> create({
    required String spaceId,
    required String name,
    required String iconKey,
    int? colorIndex,
    String? parentCategoryId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void, Failure>> delete(String id) async =>
      throw UnimplementedError();
}

class FakeTransactionsRepository implements TransactionsRepository {
  FakeTransactionsRepository(this.transactions);
  final List<Transaction> transactions;

  @override
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) => Stream.value(transactions);

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
}

class FakeBudgetsRepository implements BudgetsRepository {
  FakeBudgetsRepository(this.budgets);
  final List<Budget> budgets;

  @override
  Stream<List<Budget>> watchBySpace(String spaceId) => Stream.value(budgets);

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
// Fábricas de dado de teste
// ---------------------------------------------------------------------------

Space personalSpace({String name = 'Pessoal'}) => Space(
  id: 'space-1',
  type: SpaceType.personal,
  name: name,
  ownerId: 'user-1',
  privacy: SpacePrivacy.sharedOnly,
  status: SpaceStatus.active,
  settlementCurrency: 'BRL',
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

Category testCategory({
  String id = 'cat-1',
  String name = 'Alimentação',
  String iconKey = 'food',
}) => Category(
  id: id,
  name: name,
  iconKey: iconKey,
  isSystem: true,
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

Transaction testTransaction({
  required int minor,
  DateTime? occurredAt,
  TransactionType type = TransactionType.expense,
  String? categoryId = 'cat-1',
  String? description = 'Mercado',
  String id = 'tx-1',
}) {
  final when = occurredAt ?? DateTime.now();
  return Transaction(
    id: id,
    spaceId: 'space-1',
    createdBy: 'user-1',
    type: type,
    amount: Money.fromMinor(type.isOutflow ? -minor.abs() : minor.abs()),
    occurredAt: when,
    source: TransactionSource.manual,
    isShared: false,
    aiCategorized: false,
    createdAt: when,
    updatedAt: when,
    categoryId: categoryId,
    description: description,
  );
}

Budget testBudget({
  String id = 'bud-1',
  String categoryId = 'cat-1',
  int limitMinor = 120000,
  DateTime? startsAt,
}) => Budget(
  id: id,
  spaceId: 'space-1',
  categoryId: categoryId,
  limit: Money.fromMinor(limitMinor),
  period: BudgetPeriod.monthly,
  startsAt: startsAt ?? DateTime(DateTime.now().year, DateTime.now().month),
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

/// Monta [screen] com todos os repositórios falsos e o tema real do app.
///
/// [wrapInScaffold] existe porque as páginas de aba não trazem `Scaffold`
/// próprio — em produção o `AppShell` fornece um. Passe `false` para telas que
/// já têm o seu (`TransactionsPage`, `AppShell`).
///
/// [settle] deve ser `false` quando a tela mostra um indicador de progresso: o
/// `pumpAndSettle` nunca converge com animação infinita.
/// [transactionsRepository] e [budgetsRepository] permitem trocar o fake por um
/// que registre escritas, para os testes que tocam Salvar ou Excluir — os fakes
/// padrão só leem e lançam em qualquer escrita.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Space>? spaces,
  List<Category>? categories,
  List<Transaction> transactions = const [],
  List<Budget> budgets = const [],
  TransactionsRepository? transactionsRepository,
  BudgetsRepository? budgetsRepository,
  bool dark = false,
  bool wrapInScaffold = true,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spacesRepositoryProvider.overrideWithValue(
          FakeSpacesRepository(spaces ?? [personalSpace()]),
        ),
        categoriesRepositoryProvider.overrideWithValue(
          FakeCategoriesRepository(categories ?? [testCategory()]),
        ),
        transactionsRepositoryProvider.overrideWithValue(
          transactionsRepository ?? FakeTransactionsRepository(transactions),
        ),
        budgetsRepositoryProvider.overrideWithValue(
          budgetsRepository ?? FakeBudgetsRepository(budgets),
        ),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: wrapInScaffold ? Scaffold(body: screen) : screen,
      ),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Duas passadas bastam para os streams emitirem sem esperar animação.
    await tester.pump();
    await tester.pump();
  }
}
