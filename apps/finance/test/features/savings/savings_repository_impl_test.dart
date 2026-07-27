import 'package:core/core.dart';
import 'package:finance/features/savings/data/savings_repository_impl.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/app_harness.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

ResultSet emptyResultSet() => ResultSet(const [], const [], const []);

void main() {
  setUpAll(() => registerFallbackValue(<Object?>[]));

  late MockSqliteConnection db;
  late MockSupabaseClient supabase;
  late MockGoTrueClient auth;

  SavingsRepositoryImpl buildRepo() => SavingsRepositoryImpl(
    db: db,
    supabase: supabase,
    now: () => DateTime.utc(2026, 7, 27, 13),
    genId: () => 'goal-1',
  );

  void signedIn() {
    final user = MockUser();
    when(() => user.id).thenReturn('user-1');
    when(() => auth.currentUser).thenReturn(user);
  }

  setUp(() {
    db = MockSqliteConnection();
    supabase = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(null);
    when(() => db.execute(any(), any())).thenAnswer((_) async {
      return emptyResultSet();
    });
  });

  group('createGoal', () {
    test('exige sessão', () async {
      final result = await buildRepo().createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.objective,
        name: 'Viagem',
        targetAmount: const Money.fromMinor(800000),
      );

      expect(result.failureOrNull, isA<AuthFailure>());
    });

    test('exige nome', () async {
      signedIn();

      final result = await buildRepo().createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.objective,
        name: '   ',
        targetAmount: const Money.fromMinor(800000),
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('objetivo sem valor é recusado antes de tocar o banco', () async {
      signedIn();

      final result = await buildRepo().createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.objective,
        name: 'Viagem',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => db.execute(any(), any()));
    });

    test('percentual fora de 1..100 é recusado', () async {
      signedIn();

      for (final percentage in [0, 101, -5]) {
        final result = await buildRepo().createGoal(
          spaceId: 'space-1',
          type: SavingsGoalType.percentageIncome,
          name: 'Fatia',
          percentage: percentage,
        );

        expect(result.failureOrNull, isA<ValidationFailure>());
      }
    });

    test(
      'zera o que não pertence ao tipo, em vez de gravar dado sem forma',
      () {
        // A UI guarda valor e percentual no mesmo estado; sem essa limpeza, um
        // campo deixado para trás derrubaria a escrita no check da migration.
        signedIn();

        return buildRepo()
            .createGoal(
              spaceId: 'space-1',
              type: SavingsGoalType.percentageIncome,
              name: 'Fatia',
              percentage: 20,
              // Sujeira: valor e prazo não pertencem a uma meta percentual.
              targetAmount: const Money.fromMinor(800000),
              targetDate: DateTime(2027, 3),
            )
            .then((result) {
              final goal = result.valueOrNull!;
              expect(goal.targetAmountMinor, isNull);
              expect(goal.targetDate, isNull);
              expect(goal.percentage, 20);
            });
      },
    );

    test('prazo só sobrevive em meta por objetivo', () async {
      signedIn();

      final fixed = await buildRepo().createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.fixedAmount,
        name: 'Todo mês',
        targetAmount: const Money.fromMinor(50000),
        targetDate: DateTime(2027, 3),
      );

      expect(fixed.valueOrNull!.targetDate, isNull);
    });

    test('converte exceção do banco em DatabaseFailure', () async {
      signedIn();
      when(() => db.execute(any(), any())).thenThrow(Exception('db down'));

      final result = await buildRepo().createGoal(
        spaceId: 'space-1',
        type: SavingsGoalType.objective,
        name: 'Viagem',
        targetAmount: const Money.fromMinor(800000),
      );

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });
  });

  group('addContribution', () {
    test('exige sessão', () async {
      final result = await buildRepo().addContribution(
        goal: testGoal(),
        amount: const Money.fromMinor(40000),
      );

      expect(result.failureOrNull, isA<AuthFailure>());
    });

    test('recusa valor zero ou negativo', () async {
      signedIn();

      for (final minor in [0, -100]) {
        final result = await buildRepo().addContribution(
          goal: testGoal(),
          amount: Money.fromMinor(minor),
        );

        expect(result.failureOrNull, isA<ValidationFailure>());
      }
    });

    test('recusa moeda diferente da meta', () async {
      signedIn();

      final result = await buildRepo().addContribution(
        goal: testGoal(),
        amount: const Money.fromMinor(40000, currency: 'USD'),
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('aporte manual já nasce confirmado e no espaço da meta', () async {
      signedIn();

      final result = await buildRepo().addContribution(
        goal: testGoal(),
        amount: const Money.fromMinor(40000),
      );

      final contribution = result.valueOrNull!;
      expect(contribution.source, ContributionSource.manual);
      expect(contribution.isConfirmed, isTrue);
      expect(contribution.spaceId, 'space-1');
      expect(contribution.createdBy, 'user-1');
    });
  });

  // Teste de guarda: os mocks acima verificam o *texto* do SQL, então não pegam
  // SQL que o SQLite recusa. As tabelas do PowerSync são views com triggers
  // `INSTEAD OF` — foi exatamente aí que o UPSERT de orçamento passou meses
  // quebrado com o teste verde. Aqui as statements rodam contra views iguais.
  group('SQL de poupança contra views como as do PowerSync', () {
    late CommonDatabase local;

    setUp(() {
      local = sqlite3.openInMemory()
        ..execute('''
          CREATE TABLE savings_goals_data (
            id TEXT PRIMARY KEY, space_id TEXT, created_by TEXT,
            goal_type TEXT, name TEXT, target_amount_minor INTEGER,
            currency TEXT, target_date TEXT, percentage INTEGER,
            linked_account_id TEXT, status TEXT,
            created_at TEXT, updated_at TEXT
          );
        ''')
        ..execute('''
          CREATE TABLE savings_contributions_data (
            id TEXT PRIMARY KEY, goal_id TEXT, space_id TEXT, created_by TEXT,
            amount_minor INTEGER, currency TEXT, detected_via TEXT,
            confirmed INTEGER, contributed_at TEXT,
            created_at TEXT, updated_at TEXT
          );
        ''')
        ..execute(
          'CREATE VIEW savings_goals AS SELECT * FROM savings_goals_data;',
        )
        ..execute(
          'CREATE VIEW savings_contributions AS '
          'SELECT * FROM savings_contributions_data;',
        )
        ..execute('''
          CREATE TRIGGER goals_insert INSTEAD OF INSERT ON savings_goals BEGIN
            INSERT INTO savings_goals_data (id, space_id, created_by, goal_type,
              name, target_amount_minor, currency, target_date, percentage,
              linked_account_id, status, created_at, updated_at)
            VALUES (new.id, new.space_id, new.created_by, new.goal_type,
              new.name, new.target_amount_minor, new.currency, new.target_date,
              new.percentage, new.linked_account_id, new.status,
              new.created_at, new.updated_at);
          END;
        ''')
        ..execute('''
          CREATE TRIGGER goals_update INSTEAD OF UPDATE ON savings_goals BEGIN
            UPDATE savings_goals_data SET name = new.name,
              target_amount_minor = new.target_amount_minor,
              currency = new.currency, target_date = new.target_date,
              percentage = new.percentage,
              linked_account_id = new.linked_account_id,
              status = new.status, updated_at = new.updated_at
            WHERE id = new.id;
          END;
        ''')
        ..execute('''
          CREATE TRIGGER goals_delete INSTEAD OF DELETE ON savings_goals BEGIN
            DELETE FROM savings_goals_data WHERE id = old.id;
          END;
        ''')
        ..execute('''
          CREATE TRIGGER contrib_insert INSTEAD OF INSERT
          ON savings_contributions BEGIN
            INSERT INTO savings_contributions_data (id, goal_id, space_id,
              created_by, amount_minor, currency, detected_via, confirmed,
              contributed_at, created_at, updated_at)
            VALUES (new.id, new.goal_id, new.space_id, new.created_by,
              new.amount_minor, new.currency, new.detected_via, new.confirmed,
              new.contributed_at, new.created_at, new.updated_at);
          END;
        ''')
        ..execute('''
          CREATE TRIGGER contrib_update INSTEAD OF UPDATE
          ON savings_contributions BEGIN
            UPDATE savings_contributions_data SET confirmed = new.confirmed,
              updated_at = new.updated_at
            WHERE id = new.id;
          END;
        ''')
        ..execute('''
          CREATE TRIGGER contrib_delete INSTEAD OF DELETE
          ON savings_contributions BEGIN
            DELETE FROM savings_contributions_data WHERE id = old.id;
          END;
        ''');
    });

    tearDown(() => local.close());

    test('insert, watch e update de meta rodam na view', () {
      local.execute(
        SavingsSql.insertGoal,
        SavingsSql.insertGoalParams(
          testGoal(targetDate: DateTime(2027, 3)).toColumns(),
        ),
      );

      final rows = local.select(SavingsSql.watchGoals, ['space-1']);
      expect(rows, hasLength(1));
      expect(rows.single['goal_type'], 'objective');
      expect(rows.single['target_amount_minor'], 800000);
      expect(rows.single['target_date'], '2027-03-01');

      local.execute(
        SavingsSql.updateGoal,
        SavingsSql.updateGoalParams(
          testGoal(targetDate: DateTime(2027, 3))
              .copyWith(
                name: 'Viagem ao Peru',
                targetAmountMinor: 900000,
                status: SavingsGoalStatus.paused,
                linkedAccountId: 'acc-1',
                updatedAt: DateTime.utc(2026, 7, 28, 9),
              )
              .toColumns(),
        ),
      );

      final after = local.select('SELECT * FROM savings_goals').single;
      expect(after['name'], 'Viagem ao Peru');
      expect(after['target_amount_minor'], 900000);
      expect(after['status'], 'paused');
      expect(after['linked_account_id'], 'acc-1');
      // `created_by`, `space_id` e `created_at` ficam fora do UPDATE: são a
      // identidade da linha e continuam os originais.
      expect(after['created_by'], 'user-1');
      expect(after['created_at'], '2026-04-01T00:00:00.000Z');
    });

    test('insert e confirm de contribuição rodam na view', () {
      local
        ..execute(
          SavingsSql.insertGoal,
          SavingsSql.insertGoalParams(testGoal().toColumns()),
        )
        ..execute(
          SavingsSql.insertContribution,
          SavingsSql.insertContributionParams(
            testContribution(
              minor: 40000,
              source: ContributionSource.openFinance,
              isConfirmed: false,
            ).toColumns(),
          ),
        );

      final before = local.select(SavingsSql.watchContributions, [
        'space-1',
      ]).single;
      expect(before['confirmed'], 0);
      expect(before['detected_via'], 'open_finance');

      local.execute(SavingsSql.confirmContribution, [
        '2026-07-27T13:00:00.000Z',
        'contrib-1',
      ]);

      final after = local.select('SELECT * FROM savings_contributions').single;
      expect(after['confirmed'], 1);
      // Valor e data são do evento, não do usuário: confirmar não os move.
      expect(after['amount_minor'], 40000);
      expect(after['contributed_at'], before['contributed_at']);
    });

    test('excluir meta apaga as contribuições dela na mesma passada', () {
      local
        ..execute(
          SavingsSql.insertGoal,
          SavingsSql.insertGoalParams(testGoal().toColumns()),
        )
        ..execute(
          SavingsSql.insertGoal,
          SavingsSql.insertGoalParams(
            testGoal(id: 'goal-2', name: 'Reserva').toColumns(),
          ),
        )
        ..execute(
          SavingsSql.insertContribution,
          SavingsSql.insertContributionParams(
            testContribution(minor: 40000).toColumns(),
          ),
        )
        ..execute(
          SavingsSql.insertContribution,
          SavingsSql.insertContributionParams(
            testContribution(
              id: 'contrib-2',
              minor: 40000,
              goalId: 'goal-2',
            ).toColumns(),
          ),
        )
        // A ordem do repository: contribuições primeiro, meta depois.
        ..execute(SavingsSql.deleteContributionsOfGoal, ['goal-1'])
        ..execute(SavingsSql.deleteGoal, ['goal-1']);

      expect(local.select('SELECT * FROM savings_goals'), hasLength(1));
      // A contribuição da outra meta sobrevive: o DELETE é por `goal_id`.
      final left = local.select('SELECT * FROM savings_contributions').single;
      expect(left['goal_id'], 'goal-2');
    });

    test('a view recusa UPSERT — é por isso que não existe um aqui', () {
      // Guarda contra a regressão do orçamento: qualquer SQL novo sobre tabela
      // do PowerSync precisa de um teste que execute de verdade.
      expect(
        () => local.execute(
          'INSERT INTO savings_goals (id, space_id) VALUES (?, ?) '
          'ON CONFLICT (id) DO UPDATE SET space_id = excluded.space_id',
          ['goal-1', 'space-1'],
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
