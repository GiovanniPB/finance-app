import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:finance/features/categories/domain/category.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/presentation/transaction_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction tx({
  required int minor,
  required DateTime occurredAt,
  TransactionType type = TransactionType.expense,
  String? categoryId = 'cat-1',
  String? description = 'Mercado',
  String id = 'tx',
}) => Transaction(
  id: id,
  spaceId: 'space-1',
  createdBy: 'user-1',
  type: type,
  amount: Money.fromMinor(type.isOutflow ? -minor.abs() : minor.abs()),
  occurredAt: occurredAt,
  source: TransactionSource.manual,
  isShared: false,
  aiCategorized: false,
  createdAt: occurredAt,
  updatedAt: occurredAt,
  categoryId: categoryId,
  description: description,
);

Category food() => Category(
  id: 'cat-1',
  name: 'Alimentação',
  iconKey: 'food',
  isSystem: true,
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

Future<void> pumpList(
  WidgetTester tester,
  List<Transaction> transactions, {
  Map<String, Category>? categories,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: TransactionList(
        days: TransactionDay.groupByDay(transactions),
        categoriesById: categories ?? {'cat-1': food()},
      ),
    ),
  ),
);

void main() {
  group('formatDayLabel', () {
    final today = DateTime(2026, 7, 27);

    test('hoje e ontem viram palavra', () {
      expect(formatDayLabel(today, today: today), 'Hoje');
      expect(
        formatDayLabel(DateTime(2026, 7, 26), today: today),
        'Ontem',
      );
    });

    test('datas mais antigas usam dia e mês em pt-BR', () {
      expect(
        formatDayLabel(DateTime(2026, 7, 23), today: today),
        '23 de julho',
      );
      expect(
        formatDayLabel(DateTime(2026, 3, 5), today: today),
        '5 de março',
      );
    });

    test('ignora a hora ao comparar', () {
      expect(
        formatDayLabel(DateTime(2026, 7, 27, 23, 59), today: today),
        'Hoje',
      );
    });

    test('data futura não vira "Ontem"', () {
      expect(
        formatDayLabel(DateTime(2026, 7, 28), today: today),
        '28 de julho',
      );
    });
  });

  group('TransactionDay.groupByDay', () {
    test('agrupa por dia local', () {
      final days = TransactionDay.groupByDay([
        tx(minor: 100, occurredAt: DateTime(2026, 7, 27, 9), id: 'a'),
        tx(minor: 200, occurredAt: DateTime(2026, 7, 27, 18), id: 'b'),
        tx(minor: 300, occurredAt: DateTime(2026, 7, 26, 12), id: 'c'),
      ]);

      expect(days, hasLength(2));
      expect(days.first.transactions, hasLength(2));
      expect(days.last.transactions, hasLength(1));
    });

    test('ordena os dias do mais recente para o mais antigo', () {
      final days = TransactionDay.groupByDay([
        tx(minor: 100, occurredAt: DateTime(2026, 7, 20), id: 'a'),
        tx(minor: 200, occurredAt: DateTime(2026, 7, 27), id: 'b'),
        tx(minor: 300, occurredAt: DateTime(2026, 7, 23), id: 'c'),
      ]);

      expect(days.map((d) => d.date.day), [27, 23, 20]);
    });

    test('lista vazia devolve zero dias', () {
      expect(TransactionDay.groupByDay(const []), isEmpty);
    });

    test('total do dia soma com sinal', () {
      final days = TransactionDay.groupByDay([
        tx(minor: 14280, occurredAt: DateTime(2026, 7, 27), id: 'a'),
        tx(minor: 1250, occurredAt: DateTime(2026, 7, 27), id: 'b'),
      ]);

      expect(days.single.total.amountMinor, -15530);
    });

    test('total mistura entrada e saída', () {
      final days = TransactionDay.groupByDay([
        tx(minor: 10000, occurredAt: DateTime(2026, 7, 27), id: 'a'),
        tx(
          minor: 30000,
          occurredAt: DateTime(2026, 7, 27),
          type: TransactionType.income,
          id: 'b',
        ),
      ]);

      expect(days.single.total.amountMinor, 20000);
    });
  });

  group('TransactionList — renderização', () {
    testWidgets('mostra o rótulo do dia e o total', (tester) async {
      final today = DateTime.now();
      await pumpList(tester, [
        tx(minor: 14280, occurredAt: today, id: 'a'),
      ]);

      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('-142,80'), findsWidgets);
    });

    testWidgets('usa a descrição quando existe', (tester) async {
      await pumpList(tester, [
        tx(minor: 100, occurredAt: DateTime.now(), description: 'Padaria'),
      ]);

      expect(find.text('Padaria'), findsOneWidget);
    });

    testWidgets('cai no nome da categoria quando não há descrição', (
      tester,
    ) async {
      await pumpList(tester, [
        tx(minor: 100, occurredAt: DateTime.now(), description: null),
      ]);

      // Uma vez só: com o título já sendo o nome da categoria, repeti-lo no
      // metadado gastava uma linha para não dizer nada.
      expect(find.text('Alimentação'), findsOneWidget);
    });

    testWidgets('descrição em branco também cai na categoria', (tester) async {
      await pumpList(tester, [
        tx(minor: 100, occurredAt: DateTime.now(), description: '   '),
      ]);

      expect(find.text('Alimentação'), findsOneWidget);
    });

    testWidgets('com descrição, a categoria aparece como metadado', (
      tester,
    ) async {
      await pumpList(tester, [
        tx(minor: 100, occurredAt: DateTime.now(), description: 'Padaria'),
      ]);

      expect(find.text('Padaria'), findsOneWidget);
      expect(find.text('Alimentação'), findsOneWidget);
    });

    testWidgets('sem descrição nem categoria mostra fallback', (tester) async {
      await pumpList(
        tester,
        [
          tx(
            minor: 100,
            occurredAt: DateTime.now(),
            description: null,
            categoryId: null,
          ),
        ],
        categories: const {},
      );

      expect(find.text('Sem descrição'), findsOneWidget);
    });

    testWidgets('receita usa o sinal + e o swatch da marca', (tester) async {
      await pumpList(tester, [
        tx(
          minor: 540000,
          occurredAt: DateTime.now(),
          type: TransactionType.income,
          description: 'Salário',
        ),
      ]);

      expect(find.text('+5.400,00'), findsWidgets);
    });

    testWidgets('separa os dias em seções distintas', (tester) async {
      final today = DateTime.now();
      await pumpList(tester, [
        tx(minor: 100, occurredAt: today, id: 'a'),
        tx(
          minor: 200,
          occurredAt: today.subtract(const Duration(days: 1)),
          id: 'b',
        ),
      ]);

      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Ontem'), findsOneWidget);
      expect(find.byType(TransactionTile), findsNWidgets(2));
    });

    testWidgets('dispara onTap com a transação da linha', (tester) async {
      Transaction? tapped;
      final today = DateTime.now();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: TransactionList(
              days: TransactionDay.groupByDay([
                tx(minor: 100, occurredAt: today, id: 'tx-9'),
              ]),
              categoriesById: {'cat-1': food()},
              onTapTransaction: (t) => tapped = t,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TransactionTile));
      expect(tapped?.id, 'tx-9');
    });

    testWidgets('funciona no tema escuro', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TransactionList(
              days: TransactionDay.groupByDay([
                tx(minor: 100, occurredAt: DateTime.now()),
              ]),
              categoriesById: {'cat-1': food()},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(TransactionTile), findsOneWidget);
    });
  });
}
