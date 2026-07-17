import 'package:database/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appSchema', () {
    test('declara as tabelas sincronizáveis esperadas', () {
      final names = appSchema.tables.map((t) => t.name).toSet();
      expect(
        names,
        containsAll(<String>{
          'profiles',
          'spaces',
          'space_members',
          'accounts',
        }),
      );
    });

    test('accounts tem as colunas de domínio (sem id implícito)', () {
      final accounts = appSchema.tables.firstWhere((t) => t.name == 'accounts');
      final columns = accounts.columns.map((c) => c.name).toSet();

      expect(
        columns,
        containsAll(<String>{
          'owner_id',
          'linked_space_id',
          'name',
          'currency',
          'created_at',
          'updated_at',
        }),
      );
      // O PowerSync gerencia `id` implicitamente; não deve ser declarado.
      expect(columns, isNot(contains('id')));
    });

    test('accounts é indexado por owner_id e linked_space_id', () {
      final accounts = appSchema.tables.firstWhere((t) => t.name == 'accounts');
      final indexedColumns = accounts.indexes
          .expand((i) => i.columns.map((c) => c.column))
          .toSet();
      expect(
        indexedColumns,
        containsAll(<String>{'owner_id', 'linked_space_id'}),
      );
    });

    test('spaces tem as colunas esperadas', () {
      final spaces = appSchema.tables.firstWhere((t) => t.name == 'spaces');
      final columns = spaces.columns.map((c) => c.name).toSet();
      expect(
        columns,
        containsAll(<String>{
          'space_type',
          'name',
          'owner_id',
          'privacy_policy',
          'status',
          'settlement_currency',
          'archived_at',
          'created_at',
          'updated_at',
        }),
      );
      expect(columns, isNot(contains('id')));
    });

    test('space_members é indexado por space_id e user_id', () {
      final members = appSchema.tables.firstWhere(
        (t) => t.name == 'space_members',
      );
      final indexedColumns = members.indexes
          .expand((i) => i.columns.map((c) => c.column))
          .toSet();
      expect(indexedColumns, containsAll(<String>{'space_id', 'user_id'}));
    });
  });
}
