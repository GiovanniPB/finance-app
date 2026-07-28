import 'package:core/core.dart';
import 'package:database/database.dart';
import 'package:finance/di/providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/local_stack.dart';

/// Testes de integração da fundação do Open Finance (ADR 0005).
///
/// O que estes testes provam é que o **schema local** aceita o que a ingestão
/// vai gravar. O que eles deliberadamente **não** provam — e cada caso abaixo
/// diz qual é o seu limite — é a integridade que só existe no Postgres: as
/// tabelas locais do PowerSync são views, e nem FK nem `unique` atravessam para
/// cá. Confundir os dois seria a mesma armadilha do `UPSERT` de orçamento, que
/// passou meses verde contra um mock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Insere uma conexão direto no banco local. Ela nasce no cliente (o widget
  /// devolve o `itemId` e o app grava), então a porta da frente é legítima.
  Future<void> seedConnection(
    LocalStack stack, {
    String id = 'conn-1',
    String ownerId = 'user-1',
    String itemId = 'item-abc',
    String status = 'active',
  }) => stack.db.execute(
    'INSERT INTO open_finance_connections (id, owner_id, item_id, '
    'connector_id, connector_name, status, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      id,
      ownerId,
      itemId,
      201,
      'Itaú',
      status,
      '2026-07-28T00:00:00.000Z',
      '2026-07-28T00:00:00.000Z',
    ],
  );

  group('open_finance_connections', () {
    test('a tabela existe no schema local e é uma view', () async {
      final stack = await localStack();

      final row = await stack.db.getOptional(
        'SELECT type FROM sqlite_master '
        "WHERE name = 'open_finance_connections'",
      );

      expect(row?['type'], 'view');
    });

    test(
      'grava e relê a conexão com os campos que a lista renderiza',
      () async {
        final stack = await localStack();
        await seedConnection(stack);

        final row = await stack.db.get(
          'SELECT * FROM open_finance_connections WHERE id = ?',
          ['conn-1'],
        );

        expect(row['item_id'], 'item-abc');
        expect(row['connector_name'], 'Itaú');
        expect(row['connector_id'], 201);
        expect(row['status'], 'active');
      },
    );

    test(
      'o check de status do Postgres NÃO vale aqui — a guarda é do servidor',
      () async {
        final stack = await localStack();

        // Um status que o check da migration recusaria entra sem reclamar no
        // SQLite. Isto está aqui para ninguém tratar a tabela local como
        // validadora: quem recusa é o Postgres, na subida. A UI, por sua vez,
        // precisa tolerar um status que não conheça em vez de estourar.
        await seedConnection(
          stack,
          id: 'conn-2',
          itemId: 'item-x',
          status: 'status_que_nao_existe',
        );

        final row = await stack.db.get(
          'SELECT status FROM open_finance_connections WHERE id = ?',
          ['conn-2'],
        );
        expect(row['status'], 'status_que_nao_existe');
      },
    );
  });

  group('Colunas de Open Finance em transactions', () {
    test('external_id e description_raw persistem no lançamento', () async {
      final stack = await localStack();
      await seedSpace(stack.db);

      await stack.db.execute(
        'INSERT INTO transactions (id, space_id, created_by, type, '
        'amount_minor, currency, occurred_at, source, is_shared, '
        'ai_categorized, external_id, description_raw, description, '
        'created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, ?, ?)',
        [
          'tx-of-1',
          'space-1',
          'user-1',
          'expense',
          4599,
          'BRL',
          '2026-07-28T12:00:00.000Z',
          'open_finance',
          'pluggy-tx-123',
          'COMPRA CARTAO *IFOOD 28/07',
          'iFood',
          '2026-07-28T12:00:00.000Z',
          '2026-07-28T12:00:00.000Z',
        ],
      );

      final row = await stack.db.get(
        'SELECT * FROM transactions WHERE id = ?',
        ['tx-of-1'],
      );

      expect(row['external_id'], 'pluggy-tx-123');
      expect(row['source'], 'open_finance');
      // As duas descrições coexistem: a crua é da Pluggy, a outra é do usuário.
      // É essa separação que faz renomear um lançamento importado sobreviver à
      // próxima sincronização (ADR 0005, propriedade de dados).
      expect(row['description_raw'], 'COMPRA CARTAO *IFOOD 28/07');
      expect(row['description'], 'iFood');
    });

    test(
      'a unique de dedup NÃO existe localmente — dedup é da ingestão',
      () async {
        final stack = await localStack();
        await seedSpace(stack.db);

        Future<void> insert(String id) => stack.db.execute(
          'INSERT INTO transactions (id, space_id, account_id, created_by, '
          'type, amount_minor, currency, occurred_at, source, is_shared, '
          'ai_categorized, external_id, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?)',
          [
            id,
            'space-1',
            'acc-1',
            'user-1',
            'expense',
            1000,
            'BRL',
            '2026-07-28T12:00:00.000Z',
            'open_finance',
            'mesmo-external-id',
            '2026-07-28T12:00:00.000Z',
            '2026-07-28T12:00:00.000Z',
          ],
        );

        await insert('tx-a');
        // No Postgres isto violaria `transactions_account_external_id_key`.
        // Aqui passa — e o teste existe para que essa diferença esteja escrita
        // em algum lugar. A consequência prática: o worker de ingestão não pode
        // delegar a dedup ao banco local; ele decide antes de gravar.
        await insert('tx-b');

        final rows = await stack.db.getAll(
          'SELECT id FROM transactions WHERE external_id = ?',
          ['mesmo-external-id'],
        );
        expect(rows.length, 2);
      },
    );
  });

  group('Vínculo de conta com a conexão', () {
    test(
      'conta criada pelo repository nasce sem vínculo de Open Finance',
      () async {
        final stack = await localStack();
        final repo = stack.container.read(accountsRepositoryProvider);

        final created = await repo.create(
          name: 'Conta manual',
          currentBalance: const Money.fromMinor(250000),
        );

        expect(created.isOk, isTrue);

        final row = await stack.db.get(
          'SELECT connection_id, external_id FROM accounts WHERE name = ?',
          ['Conta manual'],
        );

        // Conta digitada não tem conexão, e é `connection_id` nulo que a
        // distingue de uma de Open Finance — onde o saldo passa a ser da
        // Pluggy em vez de snapshot informado pelo usuário.
        expect(row['connection_id'], isNull);
        expect(row['external_id'], isNull);
      },
    );

    test('conta de Open Finance guarda a conexão e o id externo', () async {
      final stack = await localStack();
      await seedConnection(stack);

      await stack.db.execute(
        'INSERT INTO accounts (id, owner_id, name, account_type, currency, '
        'current_balance_minor, is_savings_target, connection_id, '
        'external_id, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)',
        [
          'acc-of-1',
          'user-1',
          'Itaú Corrente',
          'checking',
          'BRL',
          1234567,
          'conn-1',
          'pluggy-acc-999',
          '2026-07-28T00:00:00.000Z',
          '2026-07-28T00:00:00.000Z',
        ],
      );

      final row = await stack.db.get(
        'SELECT * FROM accounts WHERE id = ?',
        ['acc-of-1'],
      );

      expect(row['connection_id'], 'conn-1');
      expect(row['external_id'], 'pluggy-acc-999');
    });

    test(
      'watchOwned enxerga a conta de Open Finance como qualquer outra',
      () async {
        final stack = await localStack();
        await seedConnection(stack);
        final repo = stack.container.read(accountsRepositoryProvider);

        await stack.db.execute(
          'INSERT INTO accounts (id, owner_id, name, account_type, currency, '
          'current_balance_minor, is_savings_target, connection_id, '
          'external_id, created_at, updated_at) '
          "VALUES ('acc-of-2', 'user-1', 'Nubank', 'credit_card', 'BRL', "
          "50000, 0, 'conn-1', 'pluggy-acc-1', "
          "'2026-07-28T00:00:00.000Z', '2026-07-28T00:00:00.000Z')",
        );

        final accounts = await repo.watchOwned().first;

        // A UI não distingue origem além do campo `source`/vínculo — é o que o
        // ADR 0005 promete nas consequências. Se `watchOwned` filtrasse conta
        // com conexão, a conta importada nunca apareceria na aba Perfil.
        expect(accounts.map((a) => a.name), contains('Nubank'));
      },
    );
  });

  group('webhook_events', () {
    test('não está no schema local — é tabela de servidor', () async {
      final stack = await localStack();

      // Server-only: fora do appSchema e fora das sync rules. Se algum dia ela
      // aparecer aqui, é sinal de que entrou numa sync rule por engano — e
      // payload de webhook no aparelho do usuário é dado que ele não pediu.
      final row = await stack.db.getOptional(
        "SELECT name FROM sqlite_master WHERE name = 'webhook_events'",
      );

      expect(row, isNull);
      expect(
        appSchema.tables.map((t) => t.name),
        isNot(contains('webhook_events')),
      );
    });
  });
}
