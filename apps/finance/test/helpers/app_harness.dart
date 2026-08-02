import 'dart:async';

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
import 'package:finance/features/open_finance/domain/open_finance_connection.dart';
import 'package:finance/features/open_finance/domain/open_finance_repository.dart';
import 'package:finance/features/profile/domain/profile.dart';
import 'package:finance/features/profile/domain/profile_repository.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:finance/features/savings/domain/savings_repository.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/space_member.dart';
import 'package:finance/features/spaces/domain/spaces_repository.dart';
import 'package:finance/features/transactions/domain/expense_split.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/domain/transactions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Perfil de mentira, reativo.
///
/// O padrão é **existir sem nome** — o estado de todo usuário criado antes da
/// fatia `nome-de-membro`. Passe `profile: null` para o caso em que a linha
/// ainda não chegou pelo bucket `user_owned`, que é diferente e tem tela
/// própria.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.profile = const Profile(id: 'user-1')});

  Profile? profile;
  final _controller = StreamController<Profile?>.broadcast();

  /// Nomes gravados, na ordem — inclusive os que o repositório recusaria.
  final List<String> saved = [];

  /// Erro a devolver em vez de gravar.
  Failure? failure;

  @override
  Stream<Profile?> watchMine() async* {
    yield profile;
    yield* _controller.stream;
  }

  @override
  Future<Result<void, Failure>> updateDisplayName(String name) async {
    saved.add(name);

    final error = failure;
    if (error != null) return Err(error);

    // A validação é a mesma do repositório de verdade: sem ela, um teste de
    // tela passaria com nome vazio que a produção recusa.
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Err(ValidationFailure('Digite um nome.'));
    }

    profile = (profile ?? const Profile(id: 'user-1')).copyWith(
      displayName: trimmed,
    );
    _controller.add(profile);
    return const Ok(null);
  }
}

/// Conexões de Open Finance em memória.
///
/// [connectToken] é o que `requestConnectToken` devolve; troque por nulo para
/// exercitar o caminho de falha (a tela mostra o estado de erro com "Tentar de
/// novo"). Nada aqui toca rede: a Edge Function é fronteira, e teste de widget
/// não deve depender dela.

class FakeOpenFinanceRepository implements OpenFinanceRepository {
  FakeOpenFinanceRepository({
    List<OpenFinanceConnection> connections = const [],
    this.connectToken = 'token-de-teste',
  }) : connections = [...connections];

  final List<OpenFinanceConnection> connections;
  final String? connectToken;

  /// Conexões gravadas, na ordem.
  final List<String> saved = [];

  /// Ids removidos, na ordem.
  final List<String> deleted = [];

  /// `itemId` recebido em cada pedido de token — nulo quando é conexão nova.
  final List<String?> tokenRequests = [];

  @override
  Stream<List<OpenFinanceConnection>> watchAll() => Stream.value(connections);

  @override
  Future<Result<String, Failure>> requestConnectToken({
    String? updateItemId,
  }) async {
    tokenRequests.add(updateItemId);
    final token = connectToken;
    return token == null
        ? const Err(NetworkFailure('Falha de teste ao pedir o token.'))
        : Ok(token);
  }

  @override
  Future<Result<OpenFinanceConnection, Failure>> save({
    required String itemId,
    int? connectorId,
    String? connectorName,
  }) async {
    saved.add(itemId);
    final connection = testConnection(
      id: 'conn-${saved.length}',
      itemId: itemId,
      connectorName: connectorName,
    );
    connections.add(connection);
    return Ok(connection);
  }

  /// Falha que [revokeAccess] deve devolver. Nulo revoga com sucesso.
  ///
  /// Existe separada de uma falha de escrita porque a ordem importa: revogar
  /// falhando **não pode** apagar a linha, e o único jeito de testar isso é
  /// poder falhar só na revogação.
  Failure? revokeFailure;

  final List<String> revoked = [];

  @override
  Future<Result<void, Failure>> revokeAccess(String connectionId) async {
    final failure = revokeFailure;
    if (failure != null) return Err(failure);
    revoked.add(connectionId);
    return const Ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    deleted.add(id);
    connections.removeWhere((c) => c.id == id);
    return const Ok(null);
  }
}

/// Conexão de exemplo para os testes.
OpenFinanceConnection testConnection({
  String id = 'conn-1',
  String itemId = 'item-1',
  String? connectorName = 'Banco de Teste',
  ConnectionStatus status = ConnectionStatus.active,
}) => OpenFinanceConnection(
  id: id,
  ownerId: 'user-1',
  itemId: itemId,
  status: status,
  connectorName: connectorName,
  createdAt: testNow,
  updatedAt: testNow,
);

/// Fakes e monta-tela compartilhados pelos testes de widget das telas.
///
/// Fakes em vez de mocks: as telas dependem de streams com comportamento, e um
/// fake explícito deixa o teste legível sem pilha de `when(...)`.

class FakeSpacesRepository implements SpacesRepository {
  FakeSpacesRepository(
    List<Space> spaces, {
    this.members = const [],
    this.code = 'WM38G4KA',
    this.failure,
  }) : spaces = [...spaces];

  final List<Space> spaces;
  final List<SpaceMember> members;

  /// Código devolvido por [inviteCode]. Fixo para o teste poder afirmá-lo.
  final String code;

  /// Quando presente, **toda** escrita falha com ele. É como os testes de
  /// mensagem de erro forçam o caminho ruim sem mockar a RPC.
  final Failure? failure;

  /// Espaços criados pela folha, na ordem.
  final List<Space> created = [];

  /// Códigos passados a [joinByCode], na ordem.
  final List<String> joined = [];

  @override
  Stream<List<Space>> watchAll() => Stream.value(spaces);

  @override
  Stream<Space?> watchById(String id) =>
      Stream.value(spaces.where((s) => s.id == id).firstOrNull);

  @override
  Stream<List<SpaceMember>> watchMembers(String spaceId) =>
      Stream.value(members.where((m) => m.spaceId == spaceId).toList());

  @override
  Future<Result<Space, Failure>> createShared({
    required SpaceType type,
    required String name,
  }) async {
    if (failure != null) return Err(failure!);
    final space = Space(
      id: 'space-novo',
      type: type,
      name: name.trim(),
      ownerId: 'user-1',
      privacy: type == SpaceType.household
          ? SpacePrivacy.fullTransparency
          : SpacePrivacy.sharedOnly,
      status: SpaceStatus.active,
      settlementCurrency: 'BRL',
      createdAt: testNow,
      updatedAt: testNow,
    );
    created.add(space);
    spaces.add(space);
    return Ok(space);
  }

  @override
  Future<Result<String, Failure>> inviteCode(String spaceId) async =>
      failure != null ? Err(failure!) : Ok(code);

  @override
  Future<Result<String, Failure>> joinByCode(String code) async {
    joined.add(code);
    return failure != null ? Err(failure!) : const Ok('space-1');
  }

  /// Nomes novos passados a [rename], na ordem.
  final List<String> renamed = [];

  /// Ids de espaço arquivados, na ordem.
  final List<String> archived = [];

  /// Papéis gravados por [changeRole], por id de membro.
  final List<({String memberId, SpaceRole role})> roleChanges = [];

  /// Ids de membro removidos, na ordem.
  final List<String> removed = [];

  /// Ids de espaço dos quais [leave] foi chamado, na ordem.
  final List<String> left = [];

  @override
  Future<Result<void, Failure>> rename({
    required String spaceId,
    required String name,
  }) async {
    if (failure != null) return Err(failure!);
    renamed.add(name.trim());
    return const Ok(null);
  }

  @override
  Future<Result<void, Failure>> archive(String spaceId) async {
    if (failure != null) return Err(failure!);
    archived.add(spaceId);
    return const Ok(null);
  }

  @override
  Future<Result<void, Failure>> changeRole({
    required String memberId,
    required SpaceRole role,
  }) async {
    if (failure != null) return Err(failure!);
    roleChanges.add((memberId: memberId, role: role));
    return const Ok(null);
  }

  @override
  Future<Result<void, Failure>> removeMember(String memberId) async {
    if (failure != null) return Err(failure!);
    removed.add(memberId);
    return const Ok(null);
  }

  @override
  Future<Result<void, Failure>> leave(String spaceId) async {
    if (failure != null) return Err(failure!);
    left.add(spaceId);
    return const Ok(null);
  }
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

/// Categorias em memória, que registram o que foi escrito.
///
/// Como o de conta e o de meta, e não como os de leitura pura: desde que editar
/// e remover categoria existem na UI, lançar em toda escrita esconderia
/// justamente o que há para testar.
class FakeCategoriesRepository implements CategoriesRepository {
  FakeCategoriesRepository([List<Category> categories = const []])
    : categories = [...categories];

  final List<Category> categories;

  final List<Category> created = [];
  final List<Category> updated = [];
  final List<String> deleted = [];

  /// Espaço passado no último `create`, para o teste afirmar que a categoria
  /// nasceu no espaço ativo.
  String? lastSpaceId;

  /// Quantos lançamentos usam cada categoria, por id. Ausente conta como zero.
  final Map<String, int> usage = {};

  /// Quando não nulo, toda escrita falha com esta [Failure] — inclusive a
  /// recusa por categoria em uso, que em produção vem do repository de verdade.
  Failure? writeFailure;

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
  }) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);

    lastSpaceId = spaceId;
    final category = Category(
      id: 'cat-nova',
      name: name,
      iconKey: iconKey,
      isSystem: false,
      createdAt: testNow,
      updatedAt: testNow,
      spaceId: spaceId,
      colorIndex: colorIndex,
      parentCategoryId: parentCategoryId,
    );
    created.add(category);
    return Ok(category);
  }

  @override
  Future<Result<Category, Failure>> update(Category category) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);
    updated.add(category);
    return Ok(category);
  }

  @override
  Future<Result<int, Failure>> countUsage(String categoryId) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);
    return Ok(usage[categoryId] ?? 0);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);
    deleted.add(id);
    return const Ok(null);
  }
}

class FakeTransactionsRepository implements TransactionsRepository {
  FakeTransactionsRepository(this.transactions, {List<ExpenseSplit>? splits})
    : splits = [...?splits];

  final List<Transaction> transactions;

  /// As partes que a tela lê. Mutáveis para o teste exercitar dividir e
  /// desfazer sem trocar de fake no meio.
  final List<ExpenseSplit> splits;

  /// Ids de lançamento passados a `splitEqually`, na ordem.
  final List<String> splitCalls = [];

  /// Ids de lançamento passados a `removeSplit`, na ordem.
  final List<String> unsplitCalls = [];

  /// Erro a devolver em vez de dividir.
  Failure? splitFailure;

  final _splits = StreamController<List<ExpenseSplit>>.broadcast();

  @override
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) => Stream.value(transactions);

  @override
  Stream<List<ExpenseSplit>> watchSplits(String transactionId) async* {
    yield [...splits.where((s) => s.transactionId == transactionId)];
    yield* _splits.stream.map(
      (all) => [...all.where((s) => s.transactionId == transactionId)],
    );
  }

  @override
  Future<Result<List<ExpenseSplit>, Failure>> splitEqually(
    String transactionId,
  ) async {
    splitCalls.add(transactionId);

    final failure = splitFailure;
    if (failure != null) return Err(failure);

    // Rateio igual entre `members`, com a mesma matemática da produção: um
    // fake que divide diferente esconderia o caso do centavo que sobra.
    final transaction = transactions.firstWhere((t) => t.id == transactionId);
    final shares = transaction.amount.abs.split(splitMembers.length);
    splits
      ..removeWhere((s) => s.transactionId == transactionId)
      ..addAll([
        for (var i = 0; i < splitMembers.length; i++)
          ExpenseSplit(
            id: 'split-$transactionId-$i',
            transactionId: transactionId,
            spaceId: transaction.spaceId,
            userId: splitMembers[i],
            amount: shares[i],
            createdAt: testNow,
            updatedAt: testNow,
          ),
      ]);
    _splits.add([...splits]);
    return Ok([...splits.where((s) => s.transactionId == transactionId)]);
  }

  @override
  Future<Result<void, Failure>> removeSplit(String transactionId) async {
    unsplitCalls.add(transactionId);
    splits.removeWhere((s) => s.transactionId == transactionId);
    _splits.add([...splits]);
    return const Ok(null);
  }

  /// Entre quem o fake rateia. Casa com os membros de `testSharedSpace()`.
  List<String> splitMembers = const ['user-1', 'user-2'];

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

  /// Conta passada em cada `addContribution`, na mesma ordem.
  ///
  /// Lista à parte, e não campo da contribuição: a conta é do **lançamento**, e
  /// a contribuição não a carrega. É o que permite ao teste afirmar que a folha
  /// respeitou o padrão de conta única.
  final List<String?> addedAccountIds = [];
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
    String? accountId,
    DateTime? contributedAt,
  }) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);

    final index = addedContributions.length + 1;
    final contribution = testContribution(
      id: 'contrib-$index',
      goalId: goal.id,
      minor: amount.amountMinor,
      contributedAt: contributedAt,
      // O fake não grava lançamento, mas devolve a contribuição já ligada a um:
      // é o que o repository de verdade faz, e sem isso a tela testaria uma
      // contribuição que não existe em produção.
      transactionId: 'tx-contrib-$index',
    );
    addedContributions.add(contribution);
    addedAccountIds.add(accountId);
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
    SavingsContribution contribution,
  ) async {
    final failure = writeFailure;
    if (failure != null) return Err(failure);
    deletedContributions.add(contribution.id);
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

/// Um espaço compartilhado de exemplo.
Space testSharedSpace({
  String id = 'space-2',
  String name = 'Viagem ao Chile',
  SpaceType type = SpaceType.group,
}) => Space(
  id: id,
  type: type,
  name: name,
  ownerId: 'user-1',
  privacy: type == SpaceType.household
      ? SpacePrivacy.fullTransparency
      : SpacePrivacy.sharedOnly,
  status: SpaceStatus.active,
  settlementCurrency: 'BRL',
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

/// Um membro de exemplo.
SpaceMember testMember({
  String id = 'member-1',
  String spaceId = 'space-2',
  String userId = 'user-1',
  SpaceRole role = SpaceRole.admin,

  /// Nulo é o padrão de propósito: é o estado de toda linha até a pessoa
  /// definir o nome no Perfil, e o que os testes de fallback precisam.
  String? displayName,
  DateTime? joinedAt,
}) => SpaceMember(
  id: id,
  spaceId: spaceId,
  userId: userId,
  role: role,
  status: MembershipStatus.active,
  displayName: displayName,
  joinedAt: joinedAt ?? testNow,
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

  /// Conexão de Open Finance que alimenta a conta. Nulo = conta digitada.
  String? connectionId,
}) => Account(
  id: id,
  ownerId: 'user-1',
  name: name,
  type: type,
  currentBalance: Money.fromMinor(balanceMinor),
  balanceAsOf: balanceAsOf ?? DateTime.utc(2026, 7),
  isSavingsTarget: isSavingsTarget,
  connectionId: connectionId,
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
  // `testNow`, e não `DateTime.now()`: o harness já sobrescreve o
  // `clockProvider` com ele, e um dado ancorado no relógio real cai fora do mês
  // que a tela está mostrando assim que o calendário vira.
  final when = occurredAt ?? testNow;
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
  startsAt: startsAt ?? DateTime(testNow.year, testNow.month),
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

/// "Agora" fixo dos testes de meta.
///
/// Toda conta de ritmo e projeção depende de hoje; sem um relógio fixo o teste
/// só passaria no dia em que foi escrito.
final testNow = DateTime(2026, 7, 27, 10);

/// Toca num alvo que pode estar fora da viewport da folha.
///
/// Vive aqui porque quatro arquivos de teste mantinham a mesma cópia: as folhas
/// são mais altas que o viewport do teste (valor, campos, teclado e as ações),
/// então o rodapé começa fora da tela e um `tap` cru cairia no vazio.
/// Rola a lista até [finder] existir e estar visível.
///
/// Diferente de `ensureVisible`, funciona com item que o `ListView` ainda **não
/// construiu** — que é o caso de qualquer coisa fora do viewport numa lista
/// longa. A aba Perfil passou a precisar disto quando ganhou a quarta seção
/// (bancos conectados): `find.text` de uma seção abaixo da dobra encontrava
/// zero widgets, e a falha lia como "a seção sumiu" quando ela apenas não
/// tinha sido construída.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await scrollTo(tester, finder);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

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

  /// Nulo por padrão: é o estado de toda linha anterior à migration
  /// 20260728000822, e o caso que a UI precisa tratar sem prometer que há
  /// lançamento a excluir junto.
  String? transactionId,
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
    transactionId: transactionId,
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
  SpacesRepository? spacesRepository,
  List<Category>? categories,
  List<Transaction> transactions = const [],
  List<Budget> budgets = const [],
  List<Account> accounts = const [],
  TransactionsRepository? transactionsRepository,
  BudgetsRepository? budgetsRepository,
  AccountsRepository? accountsRepository,
  SavingsRepository? savingsRepository,
  CategoriesRepository? categoriesRepository,
  OpenFinanceRepository? openFinanceRepository,
  ProfileRepository? profileRepository,
  OnboardingPreferences? onboardingPreferences,

  /// Estado da apresentação no boot. O padrão é `true` — "já viu" — porque é o
  /// que toda tela que não é a apresentação pressupõe.
  bool onboardingSeenAtBoot = true,

  /// Quem está usando o app. O padrão casa com o `ownerId` das fábricas de
  /// espaço, então por omissão o teste roda como quem criou — troque para
  /// exercitar a tela pelos olhos de um convidado.
  String? currentUserId = 'user-1',
  bool dark = false,
  bool wrapInScaffold = true,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spacesRepositoryProvider.overrideWithValue(
          spacesRepository ?? FakeSpacesRepository(spaces ?? [personalSpace()]),
        ),
        categoriesRepositoryProvider.overrideWithValue(
          categoriesRepository ??
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
        // Sem este override, qualquer tela que leia conexões cai no provider
        // real, que depende do PowerSync e lança no boot de teste.
        openFinanceRepositoryProvider.overrideWithValue(
          openFinanceRepository ?? FakeOpenFinanceRepository(),
        ),
        // O padrão é um perfil **sem nome**, que é o estado de todo usuário
        // que existe hoje — e o que mantém as telas de membro no fallback.
        profileRepositoryProvider.overrideWithValue(
          profileRepository ?? FakeProfileRepository(),
        ),
        // Relógio fixo: as telas de meta calculam ritmo e projeção contra hoje.
        clockProvider.overrideWithValue(() => testNow),
        // Sem isto, qualquer tela que pergunte "sou eu?" cai no provider real,
        // que pede uma sessão do Supabase que o teste não tem.
        currentUserIdProvider.overrideWithValue(currentUserId),
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
