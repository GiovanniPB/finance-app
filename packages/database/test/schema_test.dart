import 'package:database/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appSchema', () {
    test('declara as tabelas sincronizáveis esperadas', () {
      final names = appSchema.tables.map((t) => t.name).toSet();
      expect(names, containsAll(<String>{'profiles', 'accounts'}));
    });

    test('accounts tem as colunas de domínio (sem id implícito)', () {
      final accounts = appSchema.tables.firstWhere((t) => t.name == 'accounts');
      final columns = accounts.columns.map((c) => c.name).toSet();

      expect(
        columns,
        containsAll(<String>{
          'owner_id',
          'name',
          'currency',
          'created_at',
          'updated_at',
        }),
      );
      // O PowerSync gerencia `id` implicitamente; não deve ser declarado.
      expect(columns, isNot(contains('id')));
    });

    test('accounts é indexado por owner_id', () {
      final accounts = appSchema.tables.firstWhere((t) => t.name == 'accounts');
      final indexedColumns = accounts.indexes
          .expand((i) => i.columns.map((c) => c.column))
          .toSet();
      expect(indexedColumns, contains('owner_id'));
    });
  });
}
