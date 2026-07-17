import 'package:sqlite_async/sqlite_async.dart';

import '../domain/space.dart';
import '../domain/spaces_repository.dart';

/// Implementação sobre o PowerSync (SQL bruto). Leituras via `watch`
/// (reativas). Depende de [SqliteConnection] (interface implementada pelo
/// PowerSyncDatabase) para permitir teste com mocks.
class SpacesRepositoryImpl implements SpacesRepository {
  const SpacesRepositoryImpl({required this.db});

  final SqliteConnection db;

  @override
  Stream<List<Space>> watchAll() => db
      .watch('SELECT * FROM spaces ORDER BY created_at')
      .map((results) => results.map(Space.fromRow).toList());

  @override
  Stream<Space?> watchById(String id) => db
      .watch('SELECT * FROM spaces WHERE id = ? LIMIT 1', parameters: [id])
      .map((results) => results.isEmpty ? null : Space.fromRow(results.first));
}
