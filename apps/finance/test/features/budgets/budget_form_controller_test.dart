import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/budgets/domain/budget.dart';
import 'package:finance/features/budgets/domain/budgets_repository.dart';
import 'package:finance/features/budgets/presentation/budget_form_controller.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/presentation/spaces_providers.dart';
import 'package:finance/features/transactions/presentation/transactions_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Registra o que chegou no repositório, para verificar o que foi persistido.
class RecordingBudgetsRepository implements BudgetsRepository {
  RecordingBudgetsRepository({this.failure});

  /// Quando presente, toda escrita falha com este erro.
  final Failure? failure;

  final List<Budget> budgets = [];
  final List<String> deleted = [];

  String? lastSpaceId;
  String? lastCategoryId;
  Money? lastLimit;
  DateTime? lastStartsAt;
  BudgetPeriod? lastPeriod;

  @override
  Stream<List<Budget>> watchBySpace(String spaceId) => Stream.value(budgets);

  @override
  Future<Result<Budget, Failure>> upsert({
    required String spaceId,
    required String categoryId,
    required Money limit,
    required DateTime startsAt,
    BudgetPeriod period = BudgetPeriod.monthly,
  }) async {
    lastSpaceId = spaceId;
    lastCategoryId = categoryId;
    lastLimit = limit;
    lastStartsAt = startsAt;
    lastPeriod = period;

    final error = failure;
    if (error != null) return Err(error);

    final saved = testBudget(
      categoryId: categoryId,
      limitMinor: limit.amountMinor,
      startsAt: startsAt,
    );
    budgets.add(saved);
    return Ok(saved);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final error = failure;
    if (error != null) return Err(error);

    deleted.add(id);
    return const Ok(null);
  }
}

/// Container com o espaço já sincronizado e o repositório sob observação.
Future<ProviderContainer> ready(
  RecordingBudgetsRepository repo, {
  List<Space>? spaces,
}) async {
  final container = ProviderContainer(
    overrides: [
      spacesRepositoryProvider.overrideWithValue(
        FakeSpacesRepository(spaces ?? [personalSpace()]),
      ),
      budgetsRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(container.listen(activeSpaceProvider, (_, _) {}).close);

  await container.read(spacesProvider.future);
  return container;
}

void main() {
  late RecordingBudgetsRepository repo;

  setUp(() => repo = RecordingBudgetsRepository());

  BudgetFormController controller(ProviderContainer c, {Budget? editing}) =>
      c.read(budgetFormControllerProvider(editing).notifier);

  BudgetFormState stateOf(ProviderContainer c, {Budget? editing}) =>
      c.read(budgetFormControllerProvider(editing));

  group('BudgetFormState', () {
    test('começa zerado, sem categoria e sem poder salvar', () async {
      final container = await ready(repo);

      final state = stateOf(container);
      expect(state.amountMinor, 0);
      expect(state.amountLabel, '0,00');
      expect(state.categoryId, isNull);
      expect(state.isEditing, isFalse);
      expect(state.canSave, isFalse);
    });

    test('nasce preenchido quando abre para edição', () async {
      final container = await ready(repo);
      final existing = testBudget(limitMinor: 45000, categoryId: 'cat-9');

      final state = stateOf(container, editing: existing);
      expect(state.amountMinor, 45000);
      expect(state.amountLabel, '450,00');
      expect(state.categoryId, 'cat-9');
      expect(state.editingId, existing.id);
      expect(state.isEditing, isTrue);
      // Já dá para salvar sem tocar em nada: o limite existente é válido.
      expect(state.canSave, isTrue);
    });

    test('novo e edição são estados independentes', () async {
      final container = await ready(repo);
      final existing = testBudget(limitMinor: 45000);

      controller(container).pressDigit(7);

      expect(stateOf(container).amountMinor, 7);
      expect(stateOf(container, editing: existing).amountMinor, 45000);
    });
  });

  group('digitação do limite', () {
    test('os dígitos entram pela direita', () async {
      final container = await ready(repo);

      controller(container)
        ..pressDigit(1)
        ..pressDigit(2)
        ..pressDigit(0);

      expect(stateOf(container).amountLabel, '1,20');
    });

    test('apagar remove o último dígito', () async {
      final container = await ready(repo);

      controller(container)
        ..pressDigit(9)
        ..pressDigit(9)
        ..pressBackspace();

      expect(stateOf(container).amountMinor, 9);
    });

    test('só valor não habilita salvar — falta categoria', () async {
      final container = await ready(repo);

      controller(container).pressDigit(5);

      expect(stateOf(container).canSave, isFalse);
    });

    test('valor mais categoria habilita salvar', () async {
      final container = await ready(repo);

      controller(container)
        ..pressDigit(5)
        ..selectCategory('cat-1');

      expect(stateOf(container).canSave, isTrue);
    });

    test('tocar a categoria de novo desmarca e bloqueia salvar', () async {
      final container = await ready(repo);
      controller(container)
        ..pressDigit(5)
        ..selectCategory('cat-1')
        ..selectCategory(null);

      expect(stateOf(container).canSave, isFalse);
    });
  });

  group('save', () {
    test('grava o limite com starts_at no dia 1 do mês em foco', () async {
      final container = await ready(repo);
      container.read(focusedMonthProvider.notifier).select(DateTime(2026, 9));
      controller(container)
        ..pressDigit(3)
        ..pressDigit(0)
        ..pressDigit(0)
        ..pressDigit(0)
        ..pressDigit(0)
        ..selectCategory('cat-1');

      final saved = await controller(container).save();

      expect(saved, isTrue);
      expect(repo.lastSpaceId, 'space-1');
      expect(repo.lastCategoryId, 'cat-1');
      expect(repo.lastLimit, const Money.fromMinor(30000));
      expect(repo.lastStartsAt, DateTime(2026, 9));
      expect(repo.lastPeriod, BudgetPeriod.monthly);
    });

    test('reorçar em outro mês grava a partir daquele mês', () async {
      final container = await ready(repo);
      final julho = testBudget(startsAt: DateTime(2026, 7));
      container.read(focusedMonthProvider.notifier).select(DateTime(2026, 10));

      await controller(container, editing: julho).save();

      // O limite de julho fica como estava; o novo vale de outubro em diante.
      expect(repo.lastStartsAt, DateTime(2026, 10));
    });

    test('sem valor recusa e explica', () async {
      final container = await ready(repo);
      controller(container).selectCategory('cat-1');

      final saved = await controller(container).save();

      expect(saved, isFalse);
      expect(
        stateOf(container).errorMessage,
        'Informe um limite maior que zero.',
      );
      expect(repo.lastLimit, isNull);
    });

    test('sem categoria recusa e explica', () async {
      final container = await ready(repo);
      controller(container).pressDigit(5);

      final saved = await controller(container).save();

      expect(saved, isFalse);
      expect(stateOf(container).errorMessage, 'Escolha uma categoria.');
      expect(repo.lastLimit, isNull);
    });

    test('sem espaço ativo pede para aguardar o sync', () async {
      final container = await ready(repo, spaces: []);
      controller(container)
        ..pressDigit(5)
        ..selectCategory('cat-1');

      final saved = await controller(container).save();

      expect(saved, isFalse);
      expect(
        stateOf(container).errorMessage,
        'Aguarde a sincronização do seu espaço.',
      );
    });

    test('falha do repositório vira mensagem e libera o botão', () async {
      final falha = RecordingBudgetsRepository(
        failure: const DatabaseFailure('Não foi possível salvar o orçamento.'),
      );
      final container = await ready(falha);
      controller(container)
        ..pressDigit(5)
        ..selectCategory('cat-1');

      final saved = await controller(container).save();

      expect(saved, isFalse);
      expect(
        stateOf(container).errorMessage,
        'Não foi possível salvar o orçamento.',
      );
      expect(stateOf(container).isSaving, isFalse);
    });

    test('digitar depois do erro limpa a mensagem', () async {
      final container = await ready(repo);
      controller(container).selectCategory('cat-1');
      await controller(container).save();

      controller(container).pressDigit(5);

      expect(stateOf(container).errorMessage, isNull);
    });
  });

  group('remove', () {
    test('remove o orçamento em edição', () async {
      final container = await ready(repo);
      final existing = testBudget(id: 'bud-42');

      final removed = await controller(container, editing: existing).remove();

      expect(removed, isTrue);
      expect(repo.deleted, ['bud-42']);
    });

    test('não faz nada quando não está editando', () async {
      final container = await ready(repo);

      final removed = await controller(container).remove();

      expect(removed, isFalse);
      expect(repo.deleted, isEmpty);
    });

    test('falha do repositório vira mensagem', () async {
      final falha = RecordingBudgetsRepository(
        failure: const DatabaseFailure('Não foi possível remover o orçamento.'),
      );
      final container = await ready(falha);
      final existing = testBudget();

      final removed = await controller(container, editing: existing).remove();

      expect(removed, isFalse);
      expect(
        stateOf(container, editing: existing).errorMessage,
        'Não foi possível remover o orçamento.',
      );
    });
  });
}
