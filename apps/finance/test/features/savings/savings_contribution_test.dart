import 'package:core/core.dart';
import 'package:finance/features/savings/domain/savings_contribution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContributionSource', () {
    test('mapeia de e para o banco', () {
      expect(
        ContributionSource.fromDb('open_finance'),
        ContributionSource.openFinance,
      );
      expect(ContributionSource.fromDb('manual'), ContributionSource.manual);
      expect(ContributionSource.openFinance.db, 'open_finance');
      expect(ContributionSource.manual.db, 'manual');
    });

    test('recusa origem desconhecida', () {
      expect(() => ContributionSource.fromDb('csv'), throwsArgumentError);
    });
  });

  group('SavingsContribution.fromRow', () {
    Map<String, Object?> row({
      required Object? confirmed,
      Object? via = 'manual',
      Object? currency = 'BRL',
    }) => {
      'id': 'contrib-1',
      'goal_id': 'goal-1',
      'space_id': 'space-1',
      'created_by': 'user-1',
      'amount_minor': 40000,
      'currency': currency,
      'detected_via': via,
      'confirmed': confirmed,
      'contributed_at': '2026-07-18T12:00:00.000Z',
      'created_at': '2026-07-18T12:00:00.000Z',
      'updated_at': '2026-07-18T12:00:00.000Z',
    };

    test('lê um aporte manual confirmado', () {
      final contribution = SavingsContribution.fromRow(row(confirmed: 1));

      expect(contribution.amount, const Money.fromMinor(40000));
      expect(contribution.source, ContributionSource.manual);
      expect(contribution.isConfirmed, isTrue);
      expect(contribution.isPending, isFalse);
    });

    test('lê uma detecção pendente do Open Finance', () {
      final contribution = SavingsContribution.fromRow(
        row(confirmed: 0, via: 'open_finance'),
      );

      expect(contribution.source, ContributionSource.openFinance);
      expect(contribution.isPending, isTrue);
    });

    test('boolean chega como inteiro do SQLite', () {
      // O PowerSync materializa boolean como 0/1; ler com `as bool` quebraria.
      expect(
        SavingsContribution.fromRow(row(confirmed: 1)).isConfirmed,
        isTrue,
      );
      expect(
        SavingsContribution.fromRow(row(confirmed: 0)).isConfirmed,
        isFalse,
      );
    });

    test('confirmação e moeda ausentes caem no padrão', () {
      final contribution = SavingsContribution.fromRow(
        row(confirmed: null, currency: null),
      );

      expect(contribution.isConfirmed, isTrue);
      expect(contribution.amount.currency, Money.brl);
    });
  });

  group('SavingsContribution.toColumns', () {
    test('descarta o sinal — a coluna é positiva por constraint', () {
      final contribution = SavingsContribution(
        id: 'contrib-1',
        goalId: 'goal-1',
        spaceId: 'space-1',
        createdBy: 'user-1',
        amount: const Money.fromMinor(-40000),
        source: ContributionSource.manual,
        isConfirmed: true,
        contributedAt: DateTime.utc(2026, 7, 18),
        createdAt: DateTime.utc(2026, 7, 18),
        updatedAt: DateTime.utc(2026, 7, 18),
      );

      expect(contribution.toColumns()['amount_minor'], 40000);
    });

    test('leva space_id no payload', () {
      // O SQLite local não tem o trigger que o Postgres tem: sem o espaço na
      // escrita local a linha nasceria fora do bucket e sumiria da UI.
      final contribution = SavingsContribution(
        id: 'contrib-1',
        goalId: 'goal-1',
        spaceId: 'space-1',
        createdBy: 'user-1',
        amount: const Money.fromMinor(40000),
        source: ContributionSource.openFinance,
        isConfirmed: false,
        contributedAt: DateTime.utc(2026, 7, 18),
        createdAt: DateTime.utc(2026, 7, 18),
        updatedAt: DateTime.utc(2026, 7, 18),
      );

      final cols = contribution.toColumns();
      expect(cols['space_id'], 'space-1');
      expect(cols['confirmed'], 0);
      expect(cols['detected_via'], 'open_finance');
    });
  });
}
