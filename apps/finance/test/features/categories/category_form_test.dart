import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/categories/presentation/category_form_controller.dart';
import 'package:finance/features/categories/presentation/category_form_sheet.dart';
import 'package:finance/features/categories/presentation/category_icons.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/presentation/spaces_providers.dart';
import 'package:finance/features/transactions/presentation/quick_entry_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

Future<ProviderContainer> ready(
  FakeCategoriesRepository repo, {
  List<Space>? spaces,
}) async {
  final container = ProviderContainer(
    overrides: [
      spacesRepositoryProvider.overrideWithValue(
        FakeSpacesRepository(spaces ?? [personalSpace()]),
      ),
      categoriesRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(container.listen(activeSpaceProvider, (_, _) {}).close);

  await container.read(spacesProvider.future);
  return container;
}

void main() {
  late FakeCategoriesRepository repo;

  setUp(() => repo = FakeCategoriesRepository());

  CategoryFormController controller(ProviderContainer c) =>
      c.read(categoryFormControllerProvider(null).notifier);

  CategoryFormState stateOf(ProviderContainer c) =>
      c.read(categoryFormControllerProvider(null));

  group('CategoryFormController', () {
    test('começa sem nome, com ícone padrão e sem cor escolhida', () async {
      final container = await ready(repo);

      final state = stateOf(container);
      expect(state.name, isEmpty);
      expect(state.iconKey, 'other');
      expect(state.colorIndex, isNull);
      expect(state.canSave, isFalse);
    });

    test('nome preenchido habilita criar', () async {
      final container = await ready(repo);

      controller(container).editName('Academia');

      expect(stateOf(container).canSave, isTrue);
    });

    test('nome só com espaço não habilita criar', () async {
      final container = await ready(repo);

      controller(container).editName('   ');

      expect(stateOf(container).trimmedName, isEmpty);
      expect(stateOf(container).canSave, isFalse);
    });

    test('persiste nome sem espaço nas pontas, ícone e cor', () async {
      final container = await ready(repo);
      controller(container)
        ..editName('  Academia  ')
        ..selectIcon('health')
        ..selectColor(3);

      final created = await controller(container).save();

      expect(created?.id, 'cat-nova');
      expect(repo.lastSpaceId, 'space-1');
      expect(repo.created.single.name, 'Academia');
      expect(repo.created.single.iconKey, 'health');
      expect(repo.created.single.colorIndex, 3);
    });

    test('tocar a cor escolhida desmarca — volta a derivar do id', () async {
      final container = await ready(repo);
      controller(container)
        ..editName('Academia')
        ..selectColor(2)
        ..selectColor(null);

      await controller(container).save();

      expect(repo.created.single.colorIndex, isNull);
    });

    test('sem nome recusa e explica, sem chamar o repositório', () async {
      final container = await ready(repo);

      final created = await controller(container).save();

      expect(created, isNull);
      expect(
        stateOf(container).errorMessage,
        'Informe um nome para a categoria.',
      );
      expect(repo.created, isEmpty);
    });

    test('sem espaço ativo pede para aguardar o sync', () async {
      final container = await ready(repo, spaces: []);
      controller(container).editName('Academia');

      final created = await controller(container).save();

      expect(created, isNull);
      expect(
        stateOf(container).errorMessage,
        'Aguarde a sincronização do seu espaço.',
      );
      expect(repo.created, isEmpty);
    });

    test('falha do repositório vira mensagem e libera o botão', () async {
      final falha = FakeCategoriesRepository()
        ..writeFailure = const DatabaseFailure(
          'Não foi possível criar a categoria.',
        );
      final container = await ready(falha);
      controller(container).editName('Academia');

      final created = await controller(container).save();

      expect(created, isNull);
      expect(
        stateOf(container).errorMessage,
        'Não foi possível criar a categoria.',
      );
      expect(stateOf(container).isSaving, isFalse);
    });

    test('digitar depois do erro limpa a mensagem', () async {
      final container = await ready(repo);
      await controller(container).save();

      controller(container).editName('A');

      expect(stateOf(container).errorMessage, isNull);
    });
  });

  group('CategoryIcons.selectable', () {
    test('cada chave tem ícone próprio, exceto "other"', () {
      for (final key in CategoryIcons.selectable.where((k) => k != 'other')) {
        expect(
          CategoryIcons.resolve(key),
          isNot(CategoryIcons.fallback),
          reason: '$key deveria ter ícone próprio',
        );
      }
      // 'other' usa o fallback de propósito: é a categoria genérica.
      expect(CategoryIcons.resolve('other'), CategoryIcons.fallback);
    });

    test('não oferece o ícone de receita numa categoria de despesa', () {
      expect(CategoryIcons.selectable, isNot(contains('salary')));
    });
  });

  group('CategoryFormSheet', () {
    testWidgets('abre com Criar categoria desabilitado', (tester) async {
      await pumpScreen(tester, const CategoryFormSheet());

      expect(find.text('Nova categoria'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isFalse,
      );
    });

    testWidgets('mostra a prévia da linha enquanto se digita', (tester) async {
      await pumpScreen(tester, const CategoryFormSheet());

      expect(find.text('Sem nome'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Academia');
      await tester.pump();

      // Duas ocorrências: o que se digitou no campo e a prévia da linha.
      expect(find.text('Academia'), findsNWidgets(2));
      expect(find.text('Sem nome'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isTrue,
      );
    });

    testWidgets('oferece um ícone por chave selecionável', (tester) async {
      await pumpScreen(tester, const CategoryFormSheet());

      for (final key in CategoryIcons.selectable) {
        expect(find.byKey(Key('icon_$key')), findsOneWidget);
      }
    });

    testWidgets('oferece uma célula por matiz da paleta', (tester) async {
      await pumpScreen(tester, const CategoryFormSheet());

      // Seis matizes de baixa croma (ver AppTokens.categoryPalette).
      for (var index = 0; index < 6; index++) {
        expect(find.byKey(Key('color_$index')), findsOneWidget);
      }
    });

    testWidgets('a cor escolhida chega ao swatch da prévia', (tester) async {
      await pumpScreen(tester, const CategoryFormSheet());

      await tester.tap(find.byKey(const Key('color_4')));
      await tester.pump();

      expect(
        tester.widget<CategorySwatch>(find.byType(CategorySwatch)).colorIndex,
        4,
      );
    });

    testWidgets('funciona no tema escuro sem overflow', (tester) async {
      await pumpScreen(tester, const CategoryFormSheet(), dark: true);

      expect(tester.takeException(), isNull);
    });
  });

  group('saída quando não há categoria', () {
    testWidgets('o registro rápido oferece criar em vez de travar', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const QuickEntrySheet(),
        categories: [],
      );

      // Antes, isto dizia "Sincronizando categorias…" para sempre e o Salvar
      // nunca habilitava — sem categoria não se salva lançamento.
      expect(find.byKey(const Key('create_category')), findsOneWidget);
      expect(
        find.text('Nenhuma categoria sincronizada ainda.'),
        findsOneWidget,
      );
    });

    testWidgets('com categorias, o chip de criar fecha a fila', (tester) async {
      await pumpScreen(
        tester,
        const QuickEntrySheet(),
        categories: [testCategory()],
      );

      expect(find.byKey(const Key('create_category')), findsOneWidget);
      expect(find.text('Alimentação'), findsOneWidget);
    });

    testWidgets('o chip de criar abre o formulário', (tester) async {
      await pumpScreen(
        tester,
        const QuickEntrySheet(),
        categories: [testCategory()],
      );

      await tester.tap(find.byKey(const Key('create_category')));
      await tester.pumpAndSettle();

      expect(find.text('Nova categoria'), findsOneWidget);
    });
  });
}
