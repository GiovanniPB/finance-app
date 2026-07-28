import 'package:finance/features/spaces/data/spaces_repository_impl.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSqliteConnection extends Mock implements SqliteConnection {}

/// As leituras não tocam o Supabase — ele entra no construtor por causa das
/// escritas (identificar o dono) e das duas RPCs de convite. Um mock cru basta
/// aqui; a RPC de verdade foi exercitada contra o Postgres da nuvem, que é onde
/// ela pode falhar.
class MockSupabaseClient extends Mock implements SupabaseClient {}

ResultSet _rows(List<List<Object?>> rows) => ResultSet(
  const [
    'id',
    'space_type',
    'name',
    'owner_id',
    'privacy_policy',
    'status',
    'settlement_currency',
    'archived_at',
    'created_at',
    'updated_at',
  ],
  List<String?>.filled(10, null),
  rows,
);

List<Object?> _spaceRow(String id, String type) => [
  id,
  type,
  'Espaço $id',
  'user-1',
  'shared_only',
  'active',
  'BRL',
  null,
  '2026-07-17T12:00:00.000Z',
  '2026-07-17T12:00:00.000Z',
];

void main() {
  setUpAll(() => registerFallbackValue(<Object?>[]));

  late MockSqliteConnection db;

  setUp(() => db = MockSqliteConnection());

  group('watchAll', () {
    test('mapeia linhas do PowerSync para Space', () async {
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer(
        (_) => Stream.value(
          _rows([_spaceRow('s1', 'personal'), _spaceRow('s2', 'group')]),
        ),
      );

      final spaces = await SpacesRepositoryImpl(
        db: db,
        supabase: MockSupabaseClient(),
      ).watchAll().first;

      expect(spaces, hasLength(2));
      expect(spaces.first.type, SpaceType.personal);
      expect(spaces.last.type, SpaceType.group);
    });
  });

  group('watchById', () {
    test('retorna o espaço quando existe', () async {
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(_rows([_spaceRow('s1', 'household')])));

      final space = await SpacesRepositoryImpl(
        db: db,
        supabase: MockSupabaseClient(),
      ).watchById('s1').first;

      expect(space?.id, 's1');
      expect(space?.type, SpaceType.household);
    });

    test('retorna null quando não existe', () async {
      when(
        () => db.watch(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Stream.value(_rows([])));

      final space = await SpacesRepositoryImpl(
        db: db,
        supabase: MockSupabaseClient(),
      ).watchById('x').first;

      expect(space, isNull);
    });
  });
}
