import 'package:core/core.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavingsGoalType', () {
    test('mapeia de e para o banco em snake_case', () {
      expect(SavingsGoalType.fromDb('objective'), SavingsGoalType.objective);
      expect(
        SavingsGoalType.fromDb('fixed_amount'),
        SavingsGoalType.fixedAmount,
      );
      expect(
        SavingsGoalType.fromDb('percentage_income'),
        SavingsGoalType.percentageIncome,
      );

      expect(SavingsGoalType.objective.db, 'objective');
      expect(SavingsGoalType.fixedAmount.db, 'fixed_amount');
      expect(SavingsGoalType.percentageIncome.db, 'percentage_income');
    });

    test('recusa o tipo que o PRD lista mas o app não renderiza', () {
      // `recurring_challenge` está no PRD (RN-3.1) e fora do check da migration
      // de propósito: aceitar aqui produziria uma meta que nenhuma tela sabe
      // desenhar.
      expect(
        () => SavingsGoalType.fromDb('recurring_challenge'),
        throwsArgumentError,
      );
    });

    test('só objetivo acumula para sempre; os outros são mensais', () {
      expect(SavingsGoalType.objective.isMonthly, isFalse);
      expect(SavingsGoalType.fixedAmount.isMonthly, isTrue);
      expect(SavingsGoalType.percentageIncome.isMonthly, isTrue);
    });
  });

  group('SavingsGoalStatus', () {
    test('mapeia de e para o banco', () {
      expect(SavingsGoalStatus.fromDb('active'), SavingsGoalStatus.active);
      expect(
        SavingsGoalStatus.fromDb('completed'),
        SavingsGoalStatus.completed,
      );
      expect(SavingsGoalStatus.fromDb('paused'), SavingsGoalStatus.paused);
      expect(SavingsGoalStatus.paused.db, 'paused');
    });

    test('recusa situação desconhecida', () {
      expect(() => SavingsGoalStatus.fromDb('archived'), throwsArgumentError);
    });
  });

  group('SavingsGoal.fromRow', () {
    Map<String, Object?> row({
      String type = 'objective',
      Object? targetAmount = 800000,
      Object? targetDate,
      Object? percentage,
      Object? currency = 'BRL',
      Object? status = 'active',
    }) => {
      'id': 'goal-1',
      'space_id': 'space-1',
      'created_by': 'user-1',
      'goal_type': type,
      'name': 'Viagem ao Chile',
      'target_amount_minor': targetAmount,
      'currency': currency,
      'target_date': targetDate,
      'percentage': percentage,
      'linked_account_id': null,
      'status': status,
      'created_at': '2026-04-01T00:00:00.000Z',
      'updated_at': '2026-04-01T00:00:00.000Z',
    };

    test('lê uma meta por objetivo com prazo', () {
      final goal = SavingsGoal.fromRow(row(targetDate: '2027-03-01'));

      expect(goal.type, SavingsGoalType.objective);
      expect(goal.targetAmount, const Money.fromMinor(800000));
      expect(goal.targetDate, DateTime.parse('2027-03-01'));
      expect(goal.hasDeadline, isTrue);
      expect(goal.isMonthly, isFalse);
    });

    test('meta sem prazo não tem ritmo a comparar', () {
      final goal = SavingsGoal.fromRow(row());

      expect(goal.targetDate, isNull);
      expect(goal.hasDeadline, isFalse);
    });

    test('string vazia em target_date vale como nulo', () {
      // O PowerSync guarda `date` como texto, e uma coluna nula pode chegar
      // como string vazia dependendo de como a linha foi escrita.
      final goal = SavingsGoal.fromRow(row(targetDate: ''));

      expect(goal.targetDate, isNull);
    });

    test('meta percentual não tem valor-alvo', () {
      final goal = SavingsGoal.fromRow(
        row(type: 'percentage_income', targetAmount: null, percentage: 20),
      );

      expect(goal.targetAmount, isNull);
      expect(goal.percentage, 20);
      expect(goal.isMonthly, isTrue);
    });

    test('moeda e situação ausentes caem no padrão, sem quebrar a leitura', () {
      final goal = SavingsGoal.fromRow(row(currency: null, status: null));

      expect(goal.currency, Money.brl);
      expect(goal.status, SavingsGoalStatus.active);
    });
  });

  group('SavingsGoal.toColumns', () {
    test('grava target_date como date, sem hora', () {
      final goal = SavingsGoal(
        id: 'goal-1',
        spaceId: 'space-1',
        createdBy: 'user-1',
        type: SavingsGoalType.objective,
        name: 'Viagem',
        currency: Money.brl,
        status: SavingsGoalStatus.active,
        createdAt: DateTime.utc(2026, 4),
        updatedAt: DateTime.utc(2026, 4),
        targetAmountMinor: 800000,
        // Hora no fim do dia: se a conversão passasse por UTC, a data viraria
        // o dia seguinte no fuso de Brasília.
        targetDate: DateTime(2027, 3, 15, 23, 30),
      );

      expect(goal.toColumns()['target_date'], '2027-03-15');
    });

    test('a volta pelo banco preserva a meta', () {
      final goal = SavingsGoal(
        id: 'goal-1',
        spaceId: 'space-1',
        createdBy: 'user-1',
        type: SavingsGoalType.percentageIncome,
        name: '20% da renda',
        currency: Money.brl,
        status: SavingsGoalStatus.paused,
        createdAt: DateTime.utc(2026, 4),
        updatedAt: DateTime.utc(2026, 5),
        percentage: 20,
        linkedAccountId: 'acc-1',
      );

      final again = SavingsGoal.fromRow({...goal.toColumns(), 'id': goal.id});

      expect(again, goal);
    });
  });
}
