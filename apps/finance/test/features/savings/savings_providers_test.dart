import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:finance/features/savings/presentation/savings_providers.dart';
import 'package:finance/features/spaces/presentation/spaces_providers.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/presentation/transactions_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  /// Container com os fakes de poupança, espaço e transações.
  ///
  /// Espera os streams emitirem antes de devolver: os providers derivados leem
  /// `asData`, e sem essa espera todo teste veria lista vazia.
  Future<ProviderContainer> containerWith(
    FakeSavingsRepository savings, {
    List<Transaction> transactions = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        savingsRepositoryProvider.overrideWithValue(savings),
        spacesRepositoryProvider.overrideWithValue(
          FakeSpacesRepository([personalSpace()]),
        ),
        transactionsRepositoryProvider.overrideWithValue(
          FakeTransactionsRepository(transactions),
        ),
        clockProvider.overrideWithValue(() => testNow),
      ],
    );
    addTearDown(container.dispose);

    container
      ..listen(spacesProvider, (_, _) {})
      ..listen(savingsGoalsProvider, (_, _) {})
      ..listen(savingsContributionsProvider, (_, _) {})
      ..listen(monthTransactionsProvider, (_, _) {});

    // Os espaços primeiro, e só então o resto: sem espaço ativo os providers de
    // poupança emitem lista vazia de propósito, e esperar por eles antes do
    // espaço capturaria justamente esse vazio.
    await container.read(spacesProvider.future);
    await container.read(savingsGoalsProvider.future);
    await container.read(savingsContributionsProvider.future);
    await container.read(monthTransactionsProvider.future);

    return container;
  }

  group('goalProgressList', () {
    test('cruza cada meta com as contribuições dela', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [
            testGoal(),
            testGoal(
              id: 'goal-2',
              name: 'Reserva',
              targetAmountMinor: 100000,
            ),
          ],
          contributions: [
            testContribution(id: 'c1', minor: 40000),
            testContribution(id: 'c2', goalId: 'goal-2', minor: 30000),
          ],
        ),
      );

      final progress = container.read(goalProgressListProvider);

      expect(progress, hasLength(2));
      expect(
        progress.firstWhere((p) => p.goal.id == 'goal-1').contributed,
        const Money.fromMinor(40000),
      );
      expect(
        progress.firstWhere((p) => p.goal.id == 'goal-2').contributed,
        const Money.fromMinor(30000),
      );
    });

    test('meta pausada não aparece', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [
            testGoal(),
            testGoal(
              id: 'goal-2',
              name: 'Pausada',
              status: SavingsGoalStatus.paused,
            ),
          ],
        ),
      );

      final progress = container.read(goalProgressListProvider);

      expect(progress.map((p) => p.goal.id), ['goal-1']);
    });

    test('em andamento vem antes de concluída', () async {
      // Meta concluída não pede ação de ninguém; deixá-la no topo empurraria
      // para baixo justamente o que ainda depende de alguém.
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [
            testGoal(id: 'pronta', targetAmountMinor: 10000),
            testGoal(id: 'andando', targetAmountMinor: 100000),
          ],
          contributions: [
            testContribution(id: 'c1', goalId: 'pronta', minor: 10000),
            testContribution(id: 'c2', goalId: 'andando', minor: 20000),
          ],
        ),
      );

      final progress = container.read(goalProgressListProvider);

      expect(progress.map((p) => p.goal.id), ['andando', 'pronta']);
    });

    test('meta percentual lê a renda dos lançamentos do mês', () async {
      // É a resposta à questão aberta #1 do PRD: a renda é derivada dos
      // lançamentos `income`, não declarada num campo à parte.
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [
            testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
          ],
        ),
        transactions: [
          testTransaction(
            minor: 540000,
            type: TransactionType.income,
            occurredAt: testNow,
          ),
        ],
      );

      final progress = container.read(goalProgressListProvider).single;

      expect(progress.monthIncome, const Money.fromMinor(540000));
      expect(progress.target, const Money.fromMinor(108000));
      expect(progress.needsIncome, isFalse);
    });

    test('sem receita lançada, a meta percentual fica sem base', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [
            testGoal(type: SavingsGoalType.percentageIncome, percentage: 20),
          ],
        ),
      );

      expect(container.read(goalProgressListProvider).single.needsIncome, true);
    });
  });

  group('goalContributions', () {
    test('pendente sobe ao topo, o resto por data decrescente', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [
            testContribution(
              id: 'antiga',
              minor: 10000,
              contributedAt: DateTime(2026, 6, 10),
            ),
            testContribution(
              id: 'nova',
              minor: 20000,
              contributedAt: DateTime(2026, 7, 20),
            ),
            testContribution(
              id: 'pendente',
              minor: 30000,
              contributedAt: DateTime(2026, 5),
              isConfirmed: false,
            ),
            testContribution(id: 'de-outra', minor: 90000, goalId: 'goal-2'),
          ],
        ),
      );

      final ids = container
          .read(goalContributionsProvider('goal-1'))
          .map((c) => c.id);

      expect(ids, ['pendente', 'nova', 'antiga']);
    });
  });

  group('totais da tela', () {
    test('total é nulo sem meta alguma — zero mentiria', () async {
      final container = await containerWith(FakeSavingsRepository());

      expect(container.read(savingsTotalProvider), isNull);
    });

    test('total soma o acumulado de sempre de todas as metas', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [
            testGoal(),
            testGoal(id: 'goal-2', name: 'Reserva'),
          ],
          contributions: [
            testContribution(
              id: 'c1',
              minor: 40000,
              contributedAt: DateTime(2026, 5),
            ),
            testContribution(id: 'c2', minor: 30000, contributedAt: testNow),
            testContribution(id: 'c3', goalId: 'goal-2', minor: 20000),
          ],
        ),
      );

      expect(
        container.read(savingsTotalProvider),
        const Money.fromMinor(90000),
      );
    });

    test('total do mês ignora o que foi guardado em outros meses', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [
            testContribution(
              id: 'c1',
              minor: 40000,
              contributedAt: DateTime(2026, 5, 10),
            ),
            testContribution(id: 'c2', minor: 30000, contributedAt: testNow),
          ],
        ),
      );

      expect(
        container.read(savingsMonthTotalProvider),
        const Money.fromMinor(30000),
      );
    });

    test('total do mês ignora pendente e meta pausada', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [
            testGoal(),
            testGoal(
              id: 'pausada',
              status: SavingsGoalStatus.paused,
            ),
          ],
          contributions: [
            testContribution(id: 'c1', minor: 30000),
            testContribution(id: 'c2', minor: 50000, isConfirmed: false),
            testContribution(id: 'c3', goalId: 'pausada', minor: 70000),
          ],
        ),
      );

      expect(
        container.read(savingsMonthTotalProvider),
        const Money.fromMinor(30000),
      );
    });

    test('conta as detecções à espera de confirmação', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [
            testContribution(id: 'c1', minor: 10000),
            testContribution(id: 'c2', minor: 20000, isConfirmed: false),
            testContribution(id: 'c3', minor: 30000, isConfirmed: false),
          ],
        ),
      );

      expect(container.read(pendingContributionsCountProvider), 2);
    });
  });

  group('goalProgress por id', () {
    test('devolve nulo quando a meta não existe', () async {
      final container = await containerWith(FakeSavingsRepository());

      expect(container.read(goalProgressProvider('goal-1')), isNull);
    });

    test('devolve o progresso da meta pedida', () async {
      final container = await containerWith(
        FakeSavingsRepository(
          goals: [testGoal()],
          contributions: [testContribution(minor: 40000)],
        ),
      );

      final progress = container.read(goalProgressProvider('goal-1'));

      expect(progress?.contributed, const Money.fromMinor(40000));
    });
  });
}
