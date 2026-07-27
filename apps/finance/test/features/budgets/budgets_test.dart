import 'package:core/core.dart';
import 'package:finance/features/budgets/data/budgets_repository_impl.dart';
import 'package:finance/features/budgets/domain/budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

void main() {
  setUpAll(() => registerFallbackValue(<Object?>[]));

  Budget budget({int limitMinor = 120000}) => Budget(
    id: 'bud-1',
    spaceId: 'space-1',
    categoryId: 'cat-1',
    limit: Money.fromMinor(limitMinor),
    period: BudgetPeriod.monthly,
    startsAt: DateTime.utc(2026, 7),
    createdAt: DateTime.utc(2026, 7, 27, 12),
    updatedAt: DateTime.utc(2026, 7, 27, 12),
  );

  group('BudgetPeriod', () {
    test('mapeia os períodos do banco', () {
      expect(BudgetPeriod.fromDb('monthly'), BudgetPeriod.monthly);
      expect(BudgetPeriod.fromDb('weekly'), BudgetPeriod.weekly);
    });

    test('rejeita período desconhecido', () {
      expect(() => BudgetPeriod.fromDb('daily'), throwsArgumentError);
    });
  });

  group('Budget — mapeamento', () {
    test('fromRow monta o Money do limite', () {
      final parsed = Budget.fromRow({
        'id': 'bud-1',
        'space_id': 'space-1',
        'category_id': 'cat-1',
        'amount_minor': 120000,
        'currency': 'BRL',
        'period': 'monthly',
        'starts_at': '2026-07-01',
        'created_at': '2026-07-27T12:00:00.000Z',
        'updated_at': '2026-07-27T12:00:00.000Z',
      });

      expect(parsed.limit.amountMinor, 120000);
      expect(parsed.limit.currency, 'BRL');
      expect(parsed.startsAt, DateTime.parse('2026-07-01'));
    });

    test('toColumns grava starts_at como date, sem hora', () {
      expect(budget().toColumns()['starts_at'], '2026-07-01');
    });

    test('toColumns preenche dia e mês com zero à esquerda', () {
      final january = budget().copyWith(startsAt: DateTime.utc(2026, 1, 5));

      expect(january.toColumns()['starts_at'], '2026-01-05');
    });
  });

  group('BudgetUsage — limiares RN-1.3', () {
    BudgetUsage usage(int spentMinor, {int limitMinor = 120000}) => BudgetUsage(
      budget: budget(limitMinor: limitMinor),
      spent: Money.fromMinor(spentMinor),
    );

    test('abaixo de 80% não pede atenção', () {
      expect(usage(84210).needsAttention, isFalse);
      expect(usage(84210).isOver, isFalse);
      expect(usage(84210).percent, 70);
    });

    test('a partir de 80% pede atenção', () {
      expect(usage(96000).needsAttention, isTrue);
      expect(usage(96000).isOver, isFalse);
    });

    test('exatamente 80% já pede atenção', () {
      expect(usage(80, limitMinor: 100).needsAttention, isTrue);
    });

    test('exatamente 100% pede atenção mas não estourou', () {
      final exact = usage(100, limitMinor: 100);

      expect(exact.needsAttention, isTrue);
      expect(exact.isOver, isFalse);
    });

    test('acima de 100% estourou', () {
      expect(usage(31840, limitMinor: 30000).isOver, isTrue);
      expect(usage(31840, limitMinor: 30000).percent, 106);
    });

    test('remaining desconta o gasto', () {
      expect(usage(84210).remaining.amountMinor, 35790);
    });

    test('remaining nunca fica negativo', () {
      expect(usage(60000, limitMinor: 30000).remaining.isZero, isTrue);
    });

    test('limite zero não divide por zero', () {
      final zero = usage(1000, limitMinor: 0);

      expect(zero.ratio, 0);
      expect(zero.percent, 0);
      expect(zero.isOver, isFalse);
    });

    test('expõe o categoryId do orçamento', () {
      expect(usage(0).categoryId, 'cat-1');
    });
  });

  group('BudgetsRepositoryImpl', () {
    late MockSqliteConnection db;

    BudgetsRepositoryImpl buildRepo() => BudgetsRepositoryImpl(
      db: db,
      now: () => DateTime.utc(2026, 7, 27, 12),
      genId: () => 'bud-new',
    );

    setUp(() {
      db = MockSqliteConnection();
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(emptyResultSet()));
      when(
        () => db.execute(any(), any()),
      ).thenAnswer((_) async => emptyResultSet());
    });

    test('watchBySpace filtra por espaço', () {
      buildRepo().watchBySpace('space-1');

      final captured = verify(
        () => db.watch(
          captureAny(),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      expect(captured[0], contains('space_id = ?'));
      expect(captured[1], ['space-1']);
    });

    test('upsert usa ON CONFLICT espelhando a unique do Postgres', () async {
      await buildRepo().upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(120000),
        startsAt: DateTime.utc(2026, 7),
      );

      final sql =
          verify(() => db.execute(captureAny(), any())).captured.single
              as String;
      expect(
        sql,
        contains('ON CONFLICT (space_id, category_id, period, starts_at)'),
      );
      expect(sql, contains('DO UPDATE SET'));
    });

    test('upsert rejeita limite zero ou negativo', () async {
      final zero = await buildRepo().upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.zero(),
        startsAt: DateTime.utc(2026, 7),
      );
      final negative = await buildRepo().upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(-100),
        startsAt: DateTime.utc(2026, 7),
      );

      expect(zero.failureOrNull, isA<ValidationFailure>());
      expect(negative.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(any(), any()));
    });

    test('upsert usa mensal por padrão', () async {
      final result = await buildRepo().upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(120000),
        startsAt: DateTime.utc(2026, 7),
      );

      expect(result.valueOrNull?.period, BudgetPeriod.monthly);
    });

    test('upsert converte erro do banco em DatabaseFailure', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('falhou'));

      final result = await buildRepo().upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(120000),
        startsAt: DateTime.utc(2026, 7),
      );

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });

    test('delete remove por id', () async {
      final result = await buildRepo().delete('bud-1');

      expect(result, isA<Ok<void, Failure>>());
      final params =
          verify(() => db.execute(any(), captureAny())).captured.single
              as List<Object?>;
      expect(params, ['bud-1']);
    });

    test('delete converte erro do banco em DatabaseFailure', () async {
      when(() => db.execute(any(), any())).thenThrow(Exception('falhou'));

      expect(
        (await buildRepo().delete('bud-1')).failureOrNull,
        isA<DatabaseFailure>(),
      );
    });
  });
}
