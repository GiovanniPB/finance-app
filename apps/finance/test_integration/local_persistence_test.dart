import 'package:core/core.dart';
import 'package:database/database.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/accounts/domain/account.dart';
import 'package:finance/features/categories/domain/category.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/local_stack.dart';

/// Testes de integração da camada local.
///
/// Rodam contra um `PowerSyncDatabase` **de verdade**, aberto num diretório
/// temporário a partir do `appSchema`. É a única forma de exercitar a glue que
/// o CLAUDE.md §7 exclui da métrica de cobertura — `powersync_service.dart` e
/// `di/providers.dart` — e a única em que o SQL encontra as views com triggers
/// `INSTEAD OF` que o PowerSync cria de fato.
///
/// **Fora de escopo, de propósito:** connector, upload e Supabase. Provar a
/// ida ao Postgres exige rede, credenciais e uma conta — o que tornaria a
/// suíte lenta e intermitente. A fronteira de sessão entra como mock; o que se
/// prova aqui é que a escrita local funciona e que o `watch` reage.
void main() {
  // Binding comum, e **não** `IntegrationTestWidgetsFlutterBinding`: aquele
  // exige um device conectado, e estes testes não precisam de um. O que eles
  // precisam é do banco real, que abre na própria máquina. Foi o CI de Linux
  // que mostrou a diferença — no macOS o desktop conta como device e a
  // exigência passava despercebida.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Schema local', () {
    test('cria uma tabela consultável para cada tabela do appSchema', () async {
      final stack = await localStack();

      for (final table in appSchema.tables) {
        // Uma tabela que o PowerSync não tenha materializado faz isto lançar.
        await stack.db.getAll('SELECT * FROM ${table.name} LIMIT 0');
      }

      expect(appSchema.tables, isNotEmpty);
    });

    test('as tabelas do PowerSync são views, não tabelas', () async {
      final stack = await localStack();

      final row = await stack.db.getOptional(
        "SELECT type FROM sqlite_master WHERE name = 'transactions'",
      );

      // É por isso que nenhum SQL do app pode usar UPSERT: view não aceita.
      expect(row?['type'], 'view');
    });

    test('a view recusa UPSERT — a razão de todo select-then-write', () async {
      final stack = await localStack();
      await seedSpace(stack.db);

      expect(
        () => stack.db.execute(
          'INSERT INTO budgets (id, space_id, category_id, amount_minor, '
          'currency, period, starts_at, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT (space_id) DO UPDATE SET amount_minor = 1',
          [
            'b1',
            'space-1',
            'cat-1',
            100,
            'BRL',
            'monthly',
            '2026-07-01',
            '2026-07-01T00:00:00.000Z',
            '2026-07-01T00:00:00.000Z',
          ],
        ),
        throwsA(anything),
      );
    });
  });

  group('Composição (di/providers.dart)', () {
    test('todos os repositories montam sobre o banco real', () async {
      final stack = await localStack();
      final container = stack.container;

      // Ler cada provider prova que o composition root resolve as dependências
      // — é o arquivo excluído da cobertura unitária.
      expect(container.read(accountsRepositoryProvider), isNotNull);
      expect(container.read(spacesRepositoryProvider), isNotNull);
      expect(container.read(categoriesRepositoryProvider), isNotNull);
      expect(container.read(transactionsRepositoryProvider), isNotNull);
      expect(container.read(budgetsRepositoryProvider), isNotNull);
      expect(container.read(onboardingStoreProvider), isNotNull);
    });
  });

  group('Categorias', () {
    test('criar uma categoria faz o watch do espaço emitir', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      await seedSystemCategory(stack.db);
      final repository = stack.container.read(categoriesRepositoryProvider);

      // A expectativa é montada **antes** da escrita, e só depois esperada:
      // o que se prova aqui é a reatividade do `watch`, não o resultado do
      // `create` — que o teste seguinte já cobre.
      final reacted = expectLater(
        repository.watchForSpace('space-1'),
        emitsThrough(
          predicate<List<Category>>(
            (categories) => categories.length == 2,
            'a de sistema mais a criada',
          ),
        ),
      );

      final created = await repository.create(
        spaceId: 'space-1',
        name: 'Academia',
        iconKey: 'other',
        colorIndex: 2,
      );

      expect(created.isOk, isTrue);
      await reacted;
    });

    test('a categoria criada volta com a matiz escolhida', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(categoriesRepositoryProvider);

      await repository.create(
        spaceId: 'space-1',
        name: 'Academia',
        iconKey: 'gym',
        colorIndex: 3,
      );

      final categories = await repository.watchForSpace('space-1').first;
      expect(categories.single.name, 'Academia');
      expect(categories.single.colorIndex, 3);
      expect(categories.single.isSystem, isFalse);
    });
  });

  group('Lançamentos', () {
    test('criar, editar e excluir percorrem o banco real', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      await seedSystemCategory(stack.db);
      final repository = stack.container.read(transactionsRepositoryProvider);

      final created = await repository.create(
        spaceId: 'space-1',
        type: TransactionType.expense,
        amount: const Money.fromMinor(4500),
        occurredAt: DateTime.utc(2026, 7, 20, 12),
        categoryId: 'cat-1',
        description: 'Mercado',
      );
      final transaction = created.valueOrNull;
      expect(transaction, isNotNull);

      var stored = await repository.watchBySpace('space-1').first;
      expect(stored, hasLength(1));
      // O banco guarda positivo; o domínio devolve com sinal.
      expect(stored.single.amount, const Money.fromMinor(-4500));

      await repository.update(
        transaction!.copyWith(
          amount: const Money.fromMinor(-9900),
          description: 'Mercado do mês',
        ),
      );
      stored = await repository.watchBySpace('space-1').first;
      expect(stored.single.amount, const Money.fromMinor(-9900));
      expect(stored.single.description, 'Mercado do mês');

      await repository.delete(transaction.id);
      expect(await repository.watchBySpace('space-1').first, isEmpty);
    });

    test('o recorte por período não traz o mês vizinho', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(transactionsRepositoryProvider);

      for (final day in [DateTime.utc(2026, 6, 30), DateTime.utc(2026, 7, 2)]) {
        await repository.create(
          spaceId: 'space-1',
          type: TransactionType.expense,
          amount: const Money.fromMinor(1000),
          occurredAt: day,
        );
      }

      final julho = await repository
          .watchBySpace(
            'space-1',
            from: DateTime.utc(2026, 7),
            to: DateTime.utc(2026, 8),
          )
          .first;

      expect(julho, hasLength(1));
      expect(julho.single.occurredAt.month, 7);
    });
  });

  group('Orçamento', () {
    // A regressão que o mock não pegava: salvar duas vezes no mesmo mês tem de
    // substituir o limite, e não duplicar nem estourar.
    test('reorçar o mesmo mês substitui, sem duplicar', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(budgetsRepositoryProvider);

      final first = await repository.upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(120000),
        startsAt: DateTime.utc(2026, 7),
      );
      final second = await repository.upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(150000),
        startsAt: DateTime.utc(2026, 7),
      );

      final budgets = await repository.watchBySpace('space-1').first;
      expect(budgets, hasLength(1));
      expect(budgets.single.limit, const Money.fromMinor(150000));
      // Mesmo id: substituiu a linha em vez de criar outra.
      expect(second.valueOrNull?.id, first.valueOrNull?.id);
    });

    test('mês novo cria linha nova e deixa o anterior como estava', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(budgetsRepositoryProvider);

      await repository.upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(120000),
        startsAt: DateTime.utc(2026, 6),
      );
      await repository.upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(150000),
        startsAt: DateTime.utc(2026, 7),
      );

      final budgets = await repository.watchBySpace('space-1').first;
      expect(budgets, hasLength(2));
      expect(
        budgets.map((b) => b.limit.amountMinor),
        containsAll([120000, 150000]),
      );
    });

    test('remover apaga a linha', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(budgetsRepositoryProvider);

      final created = await repository.upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(120000),
        startsAt: DateTime.utc(2026, 7),
      );
      await repository.delete(created.valueOrNull!.id);

      expect(await repository.watchBySpace('space-1').first, isEmpty);
    });
  });

  group('Contas', () {
    test('criar grava todos os campos e o watch enxerga', () async {
      final stack = await localStack();
      final repository = stack.container.read(accountsRepositoryProvider);

      await repository.create(
        name: 'Nubank',
        type: AccountType.creditCard,
        currentBalance: const Money.fromMinor(42000),
        isSavingsTarget: true,
        institution: 'Nu Pagamentos',
      );

      final accounts = await repository.watchOwned().first;
      expect(accounts, hasLength(1));
      expect(accounts.single.type, AccountType.creditCard);
      expect(accounts.single.institution, 'Nu Pagamentos');
      expect(accounts.single.isSavingsTarget, isTrue);
      // Fatura é dívida: guardada positiva, lida negativa.
      expect(accounts.single.signedBalance, const Money.fromMinor(-42000));
    });

    test('editar sem mexer no valor preserva a data do saldo', () async {
      final stack = await localStack();
      final repository = stack.container.read(accountsRepositoryProvider);

      final created = await repository.create(name: 'Conta corrente');
      final account = created.valueOrNull!;

      await repository.update(account.copyWith(name: 'Conta salário'));

      final stored = (await repository.watchOwned().first).single;
      expect(stored.name, 'Conta salário');
      expect(stored.balanceAsOf, account.balanceAsOf);
    });

    test('saldo novo renova a data do saldo', () async {
      final stack = await localStack();
      final repository = stack.container.read(accountsRepositoryProvider);

      final created = await repository.create(name: 'Conta corrente');
      final account = created.valueOrNull!;

      await repository.update(
        account.copyWith(currentBalance: const Money.fromMinor(99900)),
        balanceChanged: true,
      );

      final stored = (await repository.watchOwned().first).single;
      expect(stored.balanceAsOf.isAfter(account.balanceAsOf), isTrue);
    });

    test('watchOwned não traz conta de outro dono', () async {
      final stack = await localStack();
      final repository = stack.container.read(accountsRepositoryProvider);
      await repository.create(name: 'Minha');
      await stack.db.execute(
        'INSERT INTO accounts (id, owner_id, name, account_type, currency, '
        'current_balance_minor, balance_as_of, is_savings_target, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'acc-alheia',
          'outro-usuario',
          'Do outro',
          'checking',
          'BRL',
          0,
          '2026-07-01T00:00:00.000Z',
          0,
          '2026-07-01T00:00:00.000Z',
          '2026-07-01T00:00:00.000Z',
        ],
      );

      final owned = await repository.watchOwned().first;

      expect(owned, hasLength(1));
      expect(owned.single.name, 'Minha');
    });
  });

  group('Preferência local (tabela localOnly)', () {
    test('gravar e reler a flag de apresentação', () async {
      final stack = await localStack();
      final store = stack.container.read(onboardingStoreProvider);

      expect(await store.hasSeen(), isFalse);
      expect((await store.markSeen()).isOk, isTrue);
      expect(await store.hasSeen(), isTrue);
    });

    test('marcar duas vezes é idempotente', () async {
      final stack = await localStack();
      final store = stack.container.read(onboardingStoreProvider);

      await store.markSeen();
      await store.markSeen();

      final rows = await stack.db.getAll('SELECT * FROM app_prefs');
      expect(rows, hasLength(1));
    });
  });

  group('Logout', () {
    // O comportamento que o roadmap registra como débito: a flag de
    // apresentação é local e vai embora junto com o resto.
    test('disconnectAndClear apaga dado sincronizável e preferência', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      await stack.container
          .read(accountsRepositoryProvider)
          .create(
            name: 'Nubank',
          );
      await stack.container.read(onboardingStoreProvider).markSeen();

      await stack.service.disconnectAndClear();

      expect(await stack.db.getAll('SELECT * FROM spaces'), isEmpty);
      expect(await stack.db.getAll('SELECT * FROM accounts'), isEmpty);
      expect(await stack.db.getAll('SELECT * FROM app_prefs'), isEmpty);
    });
  });
}
