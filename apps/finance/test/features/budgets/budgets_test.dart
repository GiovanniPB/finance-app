import 'package:core/core.dart';
import 'package:finance/features/budgets/data/budgets_repository_impl.dart';
import 'package:finance/features/budgets/domain/budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:sqlite_async/sqlite_async.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

/// Monta uma [Row] a partir de um mapa, para o mock devolver linha.
Row fakeRow(Map<String, Object?> values) => ResultSet(
  values.keys.toList(),
  List.filled(values.length, null),
  [values.values.toList()],
).first;

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
      when(() => db.getOptional(any(), any())).thenAnswer((_) async => null);
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

    test(
      'upsert procura o orçamento do período pela chave de negócio',
      () async {
        await buildRepo().upsert(
          spaceId: 'space-1',
          categoryId: 'cat-1',
          limit: const Money.fromMinor(120000),
          startsAt: DateTime.utc(2026, 7),
        );

        final captured = verify(
          () => db.getOptional(captureAny(), captureAny()),
        ).captured;
        expect(captured[0], BudgetSql.selectExisting);
        expect(captured[1], ['space-1', 'cat-1', 'monthly', '2026-07-01']);
      },
    );

    test('upsert insere quando não existe orçamento no período', () async {
      final result = await buildRepo().upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(120000),
        startsAt: DateTime.utc(2026, 7),
      );

      expect(result.valueOrNull?.id, 'bud-new');
      final sql =
          verify(() => db.execute(captureAny(), any())).captured.single
              as String;
      expect(sql, BudgetSql.insert);
    });

    test('upsert atualiza o limite quando já existe no período', () async {
      when(() => db.getOptional(any(), any())).thenAnswer(
        (_) async => fakeRow({
          'id': 'bud-existente',
          'created_at': '2026-06-01T09:00:00.000Z',
        }),
      );

      final result = await buildRepo().upsert(
        spaceId: 'space-1',
        categoryId: 'cat-1',
        limit: const Money.fromMinor(150000),
        startsAt: DateTime.utc(2026, 7),
      );

      // Reorçar não cria linha nova nem perde a data de criação original.
      expect(result.valueOrNull?.id, 'bud-existente');
      expect(result.valueOrNull?.limit.amountMinor, 150000);
      expect(result.valueOrNull?.createdAt, DateTime.utc(2026, 6, 1, 9));
      expect(result.valueOrNull?.updatedAt, DateTime.utc(2026, 7, 27, 12));

      final captured = verify(
        () => db.execute(captureAny(), captureAny()),
      ).captured;
      expect(captured[0], BudgetSql.update);
      expect(captured[1], [
        150000,
        'BRL',
        '2026-07-27T12:00:00.000Z',
        'bud-existente',
      ]);
    });

    test('nenhuma statement usa UPSERT — view do PowerSync não aceita', () {
      for (final sql in [
        BudgetSql.insert,
        BudgetSql.update,
        BudgetSql.selectExisting,
      ]) {
        expect(sql, isNot(contains('ON CONFLICT')));
      }
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

  // Teste de guarda: mock de conexão verifica o *texto* do SQL, então não pega
  // SQL que o SQLite recusa. As tabelas do PowerSync são views com triggers
  // `INSTEAD OF`, e view não aceita UPSERT — foi exatamente esse o bug. Aqui as
  // statements rodam contra uma view da mesma forma.
  group('SQL de orçamento contra uma view como a do PowerSync', () {
    late CommonDatabase db;

    setUp(() {
      db = sqlite3.openInMemory()
        ..execute('''
          CREATE TABLE budgets_data (
            id TEXT PRIMARY KEY, space_id TEXT, category_id TEXT,
            amount_minor INTEGER, currency TEXT, period TEXT,
            starts_at TEXT, created_at TEXT, updated_at TEXT
          );
        ''')
        ..execute('CREATE VIEW budgets AS SELECT * FROM budgets_data;')
        ..execute('''
          CREATE TRIGGER budgets_insert INSTEAD OF INSERT ON budgets BEGIN
            INSERT INTO budgets_data (id, space_id, category_id, amount_minor,
              currency, period, starts_at, created_at, updated_at)
            VALUES (new.id, new.space_id, new.category_id, new.amount_minor,
              new.currency, new.period, new.starts_at, new.created_at,
              new.updated_at);
          END;
        ''')
        ..execute('''
          CREATE TRIGGER budgets_update INSTEAD OF UPDATE ON budgets BEGIN
            UPDATE budgets_data SET amount_minor = new.amount_minor,
              currency = new.currency, updated_at = new.updated_at
            WHERE id = new.id;
          END;
        ''')
        ..execute('''
          CREATE TRIGGER budgets_delete INSTEAD OF DELETE ON budgets BEGIN
            DELETE FROM budgets_data WHERE id = old.id;
          END;
        ''');
    });

    tearDown(() => db.close());

    List<Object?> insertParams({String id = 'bud-1', int minor = 120000}) => [
      id,
      'space-1',
      'cat-1',
      minor,
      'BRL',
      'monthly',
      '2026-07-01',
      '2026-07-27T12:00:00.000Z',
      '2026-07-27T12:00:00.000Z',
    ];

    test('insert, select da chave de negócio e update rodam na view', () {
      db.execute(BudgetSql.insert, insertParams());

      final found = db.select(BudgetSql.selectExisting, [
        'space-1',
        'cat-1',
        'monthly',
        '2026-07-01',
      ]);
      expect(found.single['id'], 'bud-1');
      expect(found.single['created_at'], '2026-07-27T12:00:00.000Z');

      db.execute(BudgetSql.update, [
        150000,
        'BRL',
        '2026-07-28T10:00:00.000Z',
        'bud-1',
      ]);

      final after = db.select('SELECT * FROM budgets');
      expect(after, hasLength(1));
      expect(after.single['amount_minor'], 150000);
      expect(after.single['updated_at'], '2026-07-28T10:00:00.000Z');
    });

    test('delete por id roda na view', () {
      db
        ..execute(BudgetSql.insert, insertParams())
        ..execute(BudgetSql.deleteById, ['bud-1']);

      expect(db.select('SELECT * FROM budgets'), isEmpty);
    });

    test('a view recusa UPSERT — o motivo do select-then-write', () {
      expect(
        () => db.execute(
          '${BudgetSql.insert} ON CONFLICT (space_id, category_id, period, '
          'starts_at) DO UPDATE SET amount_minor = excluded.amount_minor',
          insertParams(),
        ),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('UPSERT'),
          ),
        ),
      );
    });
  });
}
