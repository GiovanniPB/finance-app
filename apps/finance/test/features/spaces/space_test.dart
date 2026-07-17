import 'package:finance/features/spaces/domain/space.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> row({String? archivedAt}) => {
    'id': 'space-1',
    'space_type': 'household',
    'name': 'Casa',
    'owner_id': 'user-1',
    'privacy_policy': 'full_transparency',
    'status': 'active',
    'settlement_currency': 'BRL',
    'archived_at': archivedAt,
    'created_at': '2026-07-17T12:00:00.000Z',
    'updated_at': '2026-07-17T12:00:00.000Z',
  };

  group('Space.fromRow', () {
    test('mapeia todos os campos e enums', () {
      final space = Space.fromRow(row());
      expect(space.id, 'space-1');
      expect(space.type, SpaceType.household);
      expect(space.privacy, SpacePrivacy.fullTransparency);
      expect(space.status, SpaceStatus.active);
      expect(space.settlementCurrency, 'BRL');
      expect(space.archivedAt, isNull);
    });

    test('parseia archived_at quando presente', () {
      final space = Space.fromRow(row(archivedAt: '2026-08-01T00:00:00.000Z'));
      expect(space.archivedAt, DateTime.utc(2026, 8));
    });
  });

  group('Space.toColumns', () {
    test('faz round-trip fromRow → toColumns', () {
      final columns = Space.fromRow(row()).toColumns();
      expect(columns['space_type'], 'household');
      expect(columns['privacy_policy'], 'full_transparency');
      expect(columns['status'], 'active');
      expect(columns['archived_at'], isNull);
    });
  });

  group('enums fromDb/db', () {
    test('SpaceType', () {
      expect(SpaceType.fromDb('personal'), SpaceType.personal);
      expect(SpaceType.group.db, 'group');
      expect(() => SpaceType.fromDb('x'), throwsArgumentError);
    });

    test('SpacePrivacy', () {
      expect(SpacePrivacy.fromDb('shared_only'), SpacePrivacy.sharedOnly);
      expect(SpacePrivacy.fullTransparency.db, 'full_transparency');
      expect(() => SpacePrivacy.fromDb('x'), throwsArgumentError);
    });

    test('SpaceStatus', () {
      expect(SpaceStatus.fromDb('archived'), SpaceStatus.archived);
      expect(SpaceStatus.active.db, 'active');
      expect(() => SpaceStatus.fromDb('x'), throwsArgumentError);
    });
  });

  group('getters', () {
    test('isPersonal / isArchived', () {
      final personal = Space.fromRow(row()..['space_type'] = 'personal');
      expect(personal.isPersonal, isTrue);
      final archived = Space.fromRow(row()..['status'] = 'archived');
      expect(archived.isArchived, isTrue);
    });
  });
}
