import 'package:finance/features/accounts/domain/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Account', () {
    final row = <String, Object?>{
      'id': 'acc-1',
      'owner_id': 'user-1',
      'name': 'Carteira',
      'currency': 'BRL',
      'created_at': '2026-07-14T12:00:00.000Z',
      'updated_at': '2026-07-14T12:30:00.000Z',
    };

    test('fromRow mapeia todas as colunas', () {
      final account = Account.fromRow(row);
      expect(account.id, 'acc-1');
      expect(account.ownerId, 'user-1');
      expect(account.name, 'Carteira');
      expect(account.currency, 'BRL');
      expect(account.createdAt, DateTime.utc(2026, 7, 14, 12));
      expect(account.updatedAt, DateTime.utc(2026, 7, 14, 12, 30));
    });

    test('toColumns produz chaves do schema com datas ISO UTC', () {
      final cols = Account.fromRow(row).toColumns();
      expect(cols.keys, containsAll(row.keys));
      expect(cols['created_at'], '2026-07-14T12:00:00.000Z');
    });

    test('roundtrip fromRow -> toColumns -> fromRow preserva a entidade', () {
      final original = Account.fromRow(row);
      final roundtrip = Account.fromRow(original.toColumns());
      expect(roundtrip, original);
    });
  });
}
