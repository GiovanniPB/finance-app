import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/accounts/domain/account.dart';
import 'package:finance/features/accounts/domain/accounts_repository.dart';
import 'package:finance/features/budgets/domain/budget.dart';
import 'package:finance/features/budgets/domain/budgets_repository.dart';
import 'package:finance/features/categories/domain/categories_repository.dart';
import 'package:finance/features/categories/domain/category.dart';
import 'package:finance/features/onboarding/domain/onboarding_preferences.dart';
import 'package:finance/features/onboarding/presentation/onboarding_providers.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:finance/features/savings/domain/savings_repository.dart';
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

/// Contas em memória, que também registram o que foi escrito.
///
/// Diferente dos outros fakes: as telas de conta são de escrita (criar, editar,
/// excluir), então lançar em toda escrita esconderia justamente o que há para
/// testar.
class FakeAccountsRepository implements AccountsRepository {
  FakeAccountsRepository([List<Account> accounts = const []])
    : accounts = [...accounts];

  final List<Account> accounts;

  /// Contas criadas pelo formulário, na ordem.
  final List<Account> created = [];

  /// Contas salvas pela edição, na ordem.
  final List<Account> updated = [];

  /// Ids removidos, na ordem.
  final List<String> deleted = [];

  @override
  Stream<List<Account>> watchOwned() => Stream.value(accounts);

  @override
  Stream<List<Account>> watchForSpace(String spaceId) => Stream.value(accounts);

  @override
  Future<Result<Account, Failure>> create({
    required String name,
    AccountType type = AccountType.checking,
    Money currentBalance = const Money.zero(),
    bool isSavingsTarget = false,
    String? institution,
    String? linkedSpaceId,
  }) async {
    final account = testAccount(
      id: 'acc-${created.length + 1}',
      name: name,
      type: type,
      balanceMinor: currentBalance.amountMinor,
      isSavingsTarget: isSavingsTarget,
      institution: institution,
      linkedSpaceId: linkedSpaceId,
    );
    created.add(account);
    return Ok(account);
  }

  /// `true` na última chamada de [update] em que o saldo mudou de valor.
  bool lastUpdateChangedBalance = false;

  @override
  Future<Result<Account, Failure>> update(
    Account account, {
    bool balanceChanged = false,
  }) async {
    updated.add(account);
    lastUpdateChangedBalance = balanceChanged;
    return Ok(account);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    deleted.add(id);
    return const Ok(null);
  }
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

/// Metas e contribuições em memória, que registram o que foi escrito.
///
/// Como o de conta, e não como os de leitura: as telas de meta são de escrita
/// (criar, editar, excluir, guardar valor), então lançar em toda escrita
/// esconderia justamente o que há para testar.
class FakeSavingsRepository implements SavingsRepository {
  FakeSavingsRepository({
    List<SavingsGoal> goals = const [],
    List<SavingsContribution> contributions = const [],
  }) : goals = [...goals],
       contributions = [...contributions];

  final List<SavingsGoal> goals;
  final List<SavingsContribution> contributions;

  final List<SavingsGoal> created = [];
  final List<SavingsGoal> updated = [];
  final List<String> deletedGoals = [];
  final List<SavingsContribution> addedContributions = [];
  final List<String> confirmed = [];
  final List<String> deletedContributions = [];

  /// Quando não nulo, toda escrita falha com esta [Failure] — para testar o
  /// caminho de erro da UI sem precisar de um banco quebrado.
  Failure? writeFailure;

  @override
  Stream<List<SavingsGoal>> watchGoals(String spaceId) => Stream.value(goals);

  @override
  Stream<List<SavingsContribution>> watchContributions(String spaceId) =>
      Stream.value(contributions);

  @override
  Future<Result<SavingsGoal, Failure>> createGoal({
    required String spaceId,
    required SavingsGoalType type,
    required String name,
    Money? targetAmount,
    DateTime? targetDate,
    int? percentage,
    String? linkedAccountId,
  }) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);

    final goal = testGoal(
      id: 'goal-${created.length + 1}',
      type: type,
      name: name,
      targetAmountMinor: targetAmount?.amountMinor,
      targetDate: targetDate,
      percentage: percentage,
      linkedAccountId: linkedAccountId,
    );
    created.add(goal);
    return Ok(goal);
  }

  @override
  Future<Result<SavingsGoal, Failure>> updateGoal(SavingsGoal goal) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);
    updated.add(goal);
    return Ok(goal);
  }

  @override
  Future<Result<void, Failure>> deleteGoal(String goalId) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);
    deletedGoals.add(goalId);
    return const Ok(null);
  }

  @override
  Future<Result<SavingsContribution, Failure>> addContribution({
    required SavingsGoal goal,
    required Money amount,
    DateTime? contributedAt,
  }) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);

    final contribution = testContribution(
      id: 'contrib-${addedContributions.length + 1}',
      goalId: goal.id,
      minor: amount.amountMinor,
      contributedAt: contributedAt,
    );
    addedContributions.add(contribution);
    return Ok(contribution);
  }

  @override
  Future<Result<void, Failure>> confirmContribution(
    String contributionId,
  ) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);
    confirmed.add(contributionId);
    return const Ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteContribution(
    String contributionId,
  ) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);
    deletedContributions.add(contributionId);
    return const Ok(null);
  }
}

/// Preferência de primeira execução que só conta as gravações.
class FakeOnboardingPreferences implements OnboardingPreferences {
  /// Quantas vezes a apresentação foi concluída ou pulada.
  int marked = 0;

  @override
  Future<bool> hasSeen() async => marked > 0;

  @override
  Future<Result<void, Failure>> markSeen() async {
    marked++;
    return const Ok(null);
  }
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

Account testAccount({
  String id = 'acc-1',
  String name = 'Conta corrente',
  AccountType type = AccountType.checking,
  int balanceMinor = 250000,
  bool isSavingsTarget = false,
  String? institution,
  String? linkedSpaceId,
  DateTime? balanceAsOf,
}) => Account(
  id: id,
  ownerId: 'user-1',
  name: name,
  type: type,
  currentBalance: Money.fromMinor(balanceMinor),
  balanceAsOf: balanceAsOf ?? DateTime.utc(2026, 7),
  isSavingsTarget: isSavingsTarget,
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
  institution: institution,
  linkedSpaceId: linkedSpaceId,
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
  String? accountId,
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
    accountId: accountId,
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

/// "Agora" fixo dos testes de meta.
///
/// Toda conta de ritmo e projeção depende de hoje; sem um relógio fixo o teste
/// só passaria no dia em que foi escrito.
final testNow = DateTime(2026, 7, 27, 10);

SavingsGoal testGoal({
  String id = 'goal-1',
  SavingsGoalType type = SavingsGoalType.objective,
  String name = 'Viagem ao Chile',
  int? targetAmountMinor = 800000,
  DateTime? targetDate,
  int? percentage,
  String? linkedAccountId,
  SavingsGoalStatus status = SavingsGoalStatus.active,
  DateTime? createdAt,
}) {
  final when = createdAt ?? DateTime.utc(2026, 4);
  return SavingsGoal(
    id: id,
    spaceId: 'space-1',
    createdBy: 'user-1',
    type: type,
    name: name,
    currency: Money.brl,
    status: status,
    createdAt: when,
    updatedAt: when,
    targetAmountMinor: type == SavingsGoalType.percentageIncome
        ? null
        : targetAmountMinor,
    targetDate: type == SavingsGoalType.objective ? targetDate : null,
    percentage: type == SavingsGoalType.percentageIncome
        ? (percentage ?? 20)
        : null,
    linkedAccountId: linkedAccountId,
  );
}

SavingsContribution testContribution({
  /// Obrigatório de propósito: um teste de dinheiro que não diz o valor esconde
  /// a própria premissa — e um valor igual ao default viraria argumento
  /// redundante para o analisador.
  required int minor,
  String id = 'contrib-1',
  String goalId = 'goal-1',
  DateTime? contributedAt,
  ContributionSource source = ContributionSource.manual,
  bool isConfirmed = true,
}) {
  final when = contributedAt ?? testNow;
  return SavingsContribution(
    id: id,
    goalId: goalId,
    spaceId: 'space-1',
    createdBy: 'user-1',
    amount: Money.fromMinor(minor),
    source: source,
    isConfirmed: isConfirmed,
    contributedAt: when,
    createdAt: when,
    updatedAt: when,
  );
}

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
/// padrão só leem e lançam em qualquer escrita. [accountsRepository] segue a
/// mesma ideia, mas o fake padrão de conta já registra escrita (ver
/// [FakeAccountsRepository]).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Space>? spaces,
  List<Category>? categories,
  List<Transaction> transactions = const [],
  List<Budget> budgets = const [],
  List<Account> accounts = const [],
  TransactionsRepository? transactionsRepository,
  BudgetsRepository? budgetsRepository,
  AccountsRepository? accountsRepository,
  SavingsRepository? savingsRepository,
  OnboardingPreferences? onboardingPreferences,

  /// Estado da apresentação no boot. O padrão é `true` — "já viu" — porque é o
  /// que toda tela que não é a apresentação pressupõe.
  bool onboardingSeenAtBoot = true,
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
        accountsRepositoryProvider.overrideWithValue(
          accountsRepository ?? FakeAccountsRepository(accounts),
        ),
        savingsRepositoryProvider.overrideWithValue(
          savingsRepository ?? FakeSavingsRepository(),
        ),
        // Relógio fixo: as telas de meta calculam ritmo e projeção contra hoje.
        clockProvider.overrideWithValue(() => testNow),
        onboardingStoreProvider.overrideWithValue(
          onboardingPreferences ?? FakeOnboardingPreferences(),
        ),
        onboardingSeenAtBootProvider.overrideWithValue(onboardingSeenAtBoot),
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
