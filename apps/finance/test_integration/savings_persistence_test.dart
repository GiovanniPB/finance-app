import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/local_stack.dart';

/// Poupança sobre um PowerSync **de verdade**.
///
/// Vale por si porque `savings_goals` e `savings_contributions` têm as duas
/// coisas que mock de conexão não sabe reproduzir:
///
///  • as tabelas locais são **views com triggers `INSTEAD OF`**, então SQL que
///    o SQLite recusa (UPSERT, por exemplo) só falha aqui;
///  • a exclusão de meta é uma **transação com dois DELETEs**, e um mock não
///    prova que os dois rodam nem que a contribuição de outra meta sobrevive.
void main() {
  group('meta de poupança no banco local', () {
    test('cria, lê e altera pela view', () async {
      final stack = await localStack();
      await seedSpace(stack.db);

      final repository = stack.container.read(savingsRepositoryProvider);

      final created = await repository.createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.objective,
        name: 'Viagem ao Chile',
        targetAmount: const Money.fromMinor(800000),
        targetDate: DateTime(2027, 3),
      );
      expect(created.isOk, isTrue);

      final goals = await repository.watchGoals('space-1').first;
      expect(goals, hasLength(1));
      expect(goals.single.name, 'Viagem ao Chile');
      expect(goals.single.targetAmount, const Money.fromMinor(800000));
      // `date` no Postgres, texto no SQLite: a hora não sobrevive à fronteira.
      expect(goals.single.targetDate, DateTime.parse('2027-03-01'));

      final updated = await repository.updateGoal(
        goals.single.copyWith(
          name: 'Viagem ao Peru',
          targetAmountMinor: 900000,
        ),
      );
      expect(updated.isOk, isTrue);

      final after = await repository.watchGoals('space-1').first;
      expect(after.single.name, 'Viagem ao Peru');
      expect(after.single.targetAmount, const Money.fromMinor(900000));
      // O que ficou fora do UPDATE continua o original.
      expect(after.single.createdBy, 'user-1');
      expect(after.single.spaceId, 'space-1');
    });

    test('meta percentual persiste sem valor e sem prazo', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(savingsRepositoryProvider);

      await repository.createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.percentageIncome,
        name: '20% da renda',
        percentage: 20,
      );

      final goal = (await repository.watchGoals('space-1').first).single;
      expect(goal.type, SavingsGoalType.percentageIncome);
      expect(goal.percentage, 20);
      expect(goal.targetAmountMinor, isNull);
      expect(goal.targetDate, isNull);
    });

    test('outro espaço não vê a meta', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      await seedSpace(stack.db, id: 'space-2');
      final repository = stack.container.read(savingsRepositoryProvider);

      await repository.createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.objective,
        name: 'Viagem',
        targetAmount: const Money.fromMinor(800000),
      );

      expect(await repository.watchGoals('space-2').first, isEmpty);
    });
  });

  group('contribuições no banco local', () {
    test('aporte manual entra confirmado e no espaço da meta', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(savingsRepositoryProvider);

      final goal = (await repository.createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.objective,
        name: 'Viagem',
        targetAmount: const Money.fromMinor(800000),
      )).valueOrNull!;

      final added = await repository.addContribution(
        goal: goal,
        amount: const Money.fromMinor(40000),
      );
      expect(added.isOk, isTrue);

      final contributions = await repository
          .watchContributions('space-1')
          .first;
      expect(contributions, hasLength(1));
      expect(contributions.single.amount, const Money.fromMinor(40000));
      expect(contributions.single.source, ContributionSource.manual);
      expect(contributions.single.isConfirmed, isTrue);
      // Sem o trigger que o Postgres tem, o espaço vem do Dart — se viesse
      // errado a linha sumiria da UI.
      expect(contributions.single.spaceId, 'space-1');
    });

    test('confirmar move só a confirmação, não o valor nem a data', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(savingsRepositoryProvider);

      // Uma detecção do Open Finance entra pelo banco: quem a cria é a ingestão
      // do servidor, que ainda não existe.
      await stack.db.execute(
        'INSERT INTO savings_goals (id, space_id, created_by, goal_type, name, '
        'target_amount_minor, currency, status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'goal-1',
          'space-1',
          'user-1',
          'objective',
          'Viagem',
          800000,
          'BRL',
          'active',
          '2026-04-01T00:00:00.000Z',
          '2026-04-01T00:00:00.000Z',
        ],
      );
      await stack.db.execute(
        'INSERT INTO savings_contributions (id, goal_id, space_id, created_by, '
        'amount_minor, currency, detected_via, confirmed, contributed_at, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)',
        [
          'contrib-1',
          'goal-1',
          'space-1',
          'user-1',
          30000,
          'BRL',
          'open_finance',
          '2026-07-27T09:00:00.000Z',
          '2026-07-27T09:00:00.000Z',
          '2026-07-27T09:00:00.000Z',
        ],
      );

      final before =
          (await repository.watchContributions('space-1').first).single;
      expect(before.isPending, isTrue);

      final result = await repository.confirmContribution('contrib-1');
      expect(result.isOk, isTrue);

      final after =
          (await repository.watchContributions('space-1').first).single;
      expect(after.isConfirmed, isTrue);
      expect(after.amount, before.amount);
      expect(after.contributedAt, before.contributedAt);
      expect(after.source, ContributionSource.openFinance);
    });

    test(
      'excluir meta apaga as contribuições dela e poupa as das outras',
      () async {
        // O `on delete cascade` existe no Postgres; as views locais não
        // cascateiam, então quem apaga as duas coisas é o repository — e é este
        // teste que prova que a transação inteira roda contra views de verdade.
        final stack = await localStack();
        await seedSpace(stack.db);
        final repository = stack.container.read(savingsRepositoryProvider);

        final doomed = (await repository.createGoal(
          spaceId: 'space-1',
          type: SavingsGoalType.objective,
          name: 'A excluir',
          targetAmount: const Money.fromMinor(800000),
        )).valueOrNull!;
        final kept = (await repository.createGoal(
          spaceId: 'space-1',
          type: SavingsGoalType.objective,
          name: 'A manter',
          targetAmount: const Money.fromMinor(100000),
        )).valueOrNull!;

        await repository.addContribution(
          goal: doomed,
          amount: const Money.fromMinor(40000),
        );
        await repository.addContribution(
          goal: kept,
          amount: const Money.fromMinor(10000),
        );

        expect(
          await repository.watchContributions('space-1').first,
          hasLength(2),
        );

        final deleted = await repository.deleteGoal(doomed.id);
        expect(deleted.isOk, isTrue);

        final goals = await repository.watchGoals('space-1').first;
        expect(goals.map((g) => g.name), ['A manter']);

        final left = await repository.watchContributions('space-1').first;
        expect(left, hasLength(1));
        expect(left.single.goalId, kept.id);
      },
    );

    test('remover contribuição solta não toca na meta', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      final repository = stack.container.read(savingsRepositoryProvider);

      final goal = (await repository.createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.objective,
        name: 'Viagem',
        targetAmount: const Money.fromMinor(800000),
      )).valueOrNull!;
      final contribution = (await repository.addContribution(
        goal: goal,
        amount: const Money.fromMinor(40000),
      )).valueOrNull!;

      await repository.deleteContribution(contribution.id);

      expect(await repository.watchContributions('space-1').first, isEmpty);
      expect(await repository.watchGoals('space-1').first, hasLength(1));
    });
  });

  group('o schema local tem o que a fatia precisa', () {
    test('as duas tabelas existem como view', () async {
      final stack = await localStack();

      final views = await stack.db.getAll(
        "SELECT name FROM sqlite_master WHERE type = 'view' AND name IN "
        "('savings_goals', 'savings_contributions')",
      );

      // Sem ordem: o `sqlite_master` devolve na ordem de criação do schema, que
      // não é contrato de nada.
      expect(
        views.map((row) => row['name']),
        containsAll(['savings_goals', 'savings_contributions']),
      );
    });

    test('a view de meta recusa UPSERT', () async {
      // A lição do orçamento, aplicada à tabela nova: qualquer SQL sobre tabela
      // do PowerSync precisa rodar de verdade em algum teste.
      final stack = await localStack();
      await seedSpace(stack.db);

      await expectLater(
        stack.db.execute(
          'INSERT INTO savings_goals (id, space_id) VALUES (?, ?) '
          'ON CONFLICT (id) DO UPDATE SET space_id = excluded.space_id',
          ['goal-1', 'space-1'],
        ),
        throwsA(anything),
      );
    });
  });
}
