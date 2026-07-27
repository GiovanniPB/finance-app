import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/categories/domain/categories_repository.dart';
import 'package:finance/features/categories/domain/category.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/spaces_repository.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:finance/features/transactions/domain/transactions_repository.dart';
import 'package:finance/features/transactions/presentation/quick_entry_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpacesRepository implements SpacesRepository {
  @override
  Stream<List<Space>> watchAll() => Stream.value([
    Space(
      id: 'space-1',
      type: SpaceType.personal,
      name: 'Pessoal',
      ownerId: 'user-1',
      privacy: SpacePrivacy.sharedOnly,
      status: SpaceStatus.active,
      settlementCurrency: 'BRL',
      createdAt: DateTime.utc(2026, 7),
      updatedAt: DateTime.utc(2026, 7),
    ),
  ]);

  @override
  Stream<Space?> watchById(String id) => Stream.value(null);
}

class FakeCategoriesRepository implements CategoriesRepository {
  FakeCategoriesRepository(this.categories);
  final List<Category> categories;

  @override
  Stream<List<Category>> watchForSpace(String spaceId) =>
      Stream.value(categories);

  @override
  Future<Result<Category, Failure>> create({
    required String spaceId,
    required String name,
    required String iconKey,
    int? colorIndex,
    String? parentCategoryId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void, Failure>> delete(String id) async =>
      throw UnimplementedError();
}

class RecordingTransactionsRepository implements TransactionsRepository {
  int createCalls = 0;
  Money? lastAmount;
  TransactionType? lastType;

  @override
  Stream<List<Transaction>> watchBySpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) => Stream.value(const []);

  @override
  Future<Result<Transaction, Failure>> create({
    required String spaceId,
    required TransactionType type,
    required Money amount,
    required DateTime occurredAt,
    String? accountId,
    String? categoryId,
    String? description,
    bool isShared = false,
  }) async {
    createCalls++;
    lastAmount = amount;
    lastType = type;
    return Ok(
      Transaction(
        id: 'tx-1',
        spaceId: spaceId,
        createdBy: 'user-1',
        type: type,
        amount: amount,
        occurredAt: occurredAt,
        source: TransactionSource.manual,
        isShared: isShared,
        aiCategorized: false,
        createdAt: occurredAt,
        updatedAt: occurredAt,
        categoryId: categoryId,
      ),
    );
  }

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async =>
      throw UnimplementedError();

  @override
  Future<Result<void, Failure>> delete(String id) async =>
      throw UnimplementedError();
}

Category food() => Category(
  id: 'cat-1',
  name: 'Alimentação',
  iconKey: 'food',
  isSystem: true,
  createdAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 7),
);

Future<void> pumpSheet(
  WidgetTester tester, {
  required RecordingTransactionsRepository repo,
  List<Category>? categories,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spacesRepositoryProvider.overrideWithValue(FakeSpacesRepository()),
        categoriesRepositoryProvider.overrideWithValue(
          FakeCategoriesRepository(categories ?? [food()]),
        ),
        transactionsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: QuickEntrySheet()),
      ),
    ),
  );
  // Deixa os streams de espaço e categoria emitirem.
  await tester.pumpAndSettle();
}

/// Toca a tecla numérica com o rótulo informado.
Future<void> tapKey(WidgetTester tester, String digit) async {
  await tester.tap(
    find.descendant(of: find.byType(InkWell), matching: find.text(digit)).first,
  );
  await tester.pump();
}

void main() {
  group('QuickEntrySheet', () {
    testWidgets('abre com valor zerado e Salvar desabilitado', (tester) async {
      await pumpSheet(tester, repo: RecordingTransactionsRepository());

      expect(find.byKey(AmountDisplay.valueKey), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '0,00',
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, isFalse);
    });

    testWidgets('o teclado preenche centavos da direita para a esquerda', (
      tester,
    ) async {
      await pumpSheet(tester, repo: RecordingTransactionsRepository());

      await tapKey(tester, '1');
      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '0,01',
      );

      await tapKey(tester, '4');
      await tapKey(tester, '2');
      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '1,42',
      );
    });

    testWidgets('não existe tecla de vírgula — o separador é implícito', (
      tester,
    ) async {
      await pumpSheet(tester, repo: RecordingTransactionsRepository());

      expect(find.text(','), findsNothing);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    });

    testWidgets('backspace apaga o último dígito', (tester) async {
      await pumpSheet(tester, repo: RecordingTransactionsRepository());

      await tapKey(tester, '1');
      await tapKey(tester, '5');
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(AmountDisplay.valueKey)).data,
        '0,01',
      );
    });

    testWidgets('mostra os chips de categoria sincronizados', (tester) async {
      await pumpSheet(tester, repo: RecordingTransactionsRepository());

      expect(find.text('Alimentação'), findsOneWidget);
    });

    testWidgets('sem categorias avisa que está sincronizando', (tester) async {
      await pumpSheet(
        tester,
        repo: RecordingTransactionsRepository(),
        categories: const [],
      );

      expect(find.text('Sincronizando categorias…'), findsOneWidget);
    });

    testWidgets('Salvar habilita com valor + categoria', (tester) async {
      await pumpSheet(tester, repo: RecordingTransactionsRepository());

      await tapKey(tester, '5');
      await tester.tap(find.text('Alimentação'));
      await tester.pump();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isTrue,
      );
    });

    testWidgets('o caminho mínimo é três toques', (tester) async {
      final repo = RecordingTransactionsRepository();
      await pumpSheet(tester, repo: repo);

      // 1) valor, 2) categoria, 3) salvar
      await tapKey(tester, '5');
      await tester.tap(find.text('Alimentação'));
      await tester.pump();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(repo.lastAmount?.amountMinor, 5);
      expect(repo.lastType, TransactionType.expense);
    });

    testWidgets('alternar para Receita muda o tipo persistido', (tester) async {
      final repo = RecordingTransactionsRepository();
      await pumpSheet(tester, repo: repo);

      await tester.tap(find.text('Receita'));
      await tester.pump();
      await tapKey(tester, '5');
      await tester.tap(find.text('Alimentação'));
      await tester.pump();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(repo.lastType, TransactionType.income);
    });

    testWidgets('tocar a categoria selecionada desmarca', (tester) async {
      await pumpSheet(tester, repo: RecordingTransactionsRepository());

      await tapKey(tester, '5');
      await tester.tap(find.text('Alimentação'));
      await tester.pump();
      await tester.tap(find.text('Alimentação'));
      await tester.pump();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isFalse,
      );
    });

    testWidgets('funciona no tema escuro', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spacesRepositoryProvider.overrideWithValue(FakeSpacesRepository()),
            categoriesRepositoryProvider.overrideWithValue(
              FakeCategoriesRepository([food()]),
            ),
            transactionsRepositoryProvider.overrideWithValue(
              RecordingTransactionsRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: QuickEntrySheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Salvar'), findsOneWidget);
    });
  });
}
