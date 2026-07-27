import 'package:core/core.dart';
import 'package:finance/features/savings/domain/savings_goal.dart';
import 'package:finance/features/savings/presentation/goal_form_sheet.dart';
import 'package:finance/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Toca num alvo que pode estar fora da viewport da folha.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  /// Abre a folha já montada, sem depender de um botão da tela de trás.
  ///
  /// Numa viewport de telefone de verdade (390×844), e não nos 800×600 padrão
  /// do `flutter_test`: a pergunta "o teclado cabe?" só tem sentido no tamanho
  /// do aparelho alvo, e 600px reprovaria uma folha que na mão funciona.
  Future<void> pumpSheet(
    WidgetTester tester, {
    required FakeSavingsRepository savings,
    SavingsGoal? editing,
    List<Transaction> transactions = const [],
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      GoalFormSheet(editing: editing),
      savingsRepository: savings,
      transactions: transactions,
    );
  }

  group('passo 1 — escolher o tipo', () {
    testWidgets('oferece os três tipos, com objetivo já marcado', (
      tester,
    ) async {
      await pumpSheet(tester, savings: FakeSavingsRepository());

      expect(find.text('Por objetivo'), findsOneWidget);
      expect(find.text('Valor fixo mensal'), findsOneWidget);
      expect(find.text('Percentual da renda'), findsOneWidget);
      // O tipo mais comum já vem escolhido: uma tela de escolha sem nada
      // marcado cobra um toque a mais do caminho dominante.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byKey(const Key('goal_form_continue')), findsOneWidget);
    });

    testWidgets('cada tipo traz a frase que o explica', (tester) async {
      await pumpSheet(tester, savings: FakeSavingsRepository());

      // Linhas em vez de chips existem justamente por causa dessa frase.
      expect(find.textContaining('Um valor e um prazo'), findsOneWidget);
      expect(find.textContaining('O mesmo valor todo mês'), findsOneWidget);
      expect(find.textContaining('Uma fatia do que entrar'), findsOneWidget);
    });

    testWidgets('o quarto tipo do PRD não é oferecido', (tester) async {
      await pumpSheet(tester, savings: FakeSavingsRepository());

      expect(find.textContaining('52 semanas'), findsNothing);
      expect(find.textContaining('desafio'), findsNothing);
    });
  });

  group('passo 2 — objetivo', () {
    testWidgets('pede valor-alvo e cria a meta', (tester) async {
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings);

      await tapVisible(tester, find.byKey(const Key('goal_form_continue')));

      expect(find.text('VALOR-ALVO'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('goal_name')), 'Viagem');
      await tester.pumpAndSettle();

      // O valor é acumulador de centavos: seis dígitos dão R$ 8.000,00.
      for (final digit in [8, 0, 0, 0, 0, 0]) {
        await tapVisible(tester, find.text('$digit').last);
      }

      await tapVisible(tester, find.byKey(const Key('goal_form_save')));

      expect(savings.created, hasLength(1));
      expect(savings.created.single.name, 'Viagem');
      expect(savings.created.single.type, SavingsGoalType.objective);
      expect(savings.created.single.targetAmountMinor, 800000);
    });

    testWidgets('sem valor, o Salvar explica o que falta', (tester) async {
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings);

      await tapVisible(tester, find.byKey(const Key('goal_form_continue')));
      await tester.enterText(find.byKey(const Key('goal_name')), 'Viagem');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('goal_form_save')));

      expect(find.byKey(const Key('goal_form_error')), findsOneWidget);
      expect(find.textContaining('valor maior que zero'), findsOneWidget);
      expect(savings.created, isEmpty);
    });

    testWidgets('dá para voltar e trocar o tipo', (tester) async {
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings);

      await tapVisible(tester, find.byKey(const Key('goal_form_continue')));
      expect(find.byKey(const Key('goal_form_back')), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('goal_form_back')));
      await tapVisible(
        tester,
        find.byKey(const Key('goal_type_percentage_income')),
      );
      await tapVisible(tester, find.byKey(const Key('goal_form_continue')));

      expect(find.text('QUANTO DA RENDA'), findsOneWidget);
    });

    testWidgets('o teclado numérico cabe inteiro na folha', (tester) async {
      // A folha é de dois passos justamente para isso: na de editar conta a
      // última fileira do teclado fica cortada, e é um alvo de toque partido.
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings);

      await tapVisible(tester, find.byKey(const Key('goal_form_continue')));

      final zero = find.text('0').last;
      expect(zero, findsOneWidget);
      final rect = tester.getRect(zero);
      expect(rect.bottom, lessThanOrEqualTo(844));
    });
  });

  group('passo 2 — percentual da renda', () {
    Future<void> openPercentage(WidgetTester tester) async {
      await tapVisible(
        tester,
        find.byKey(const Key('goal_type_percentage_income')),
      );
      await tapVisible(tester, find.byKey(const Key('goal_form_continue')));
    }

    testWidgets('oferece cinco presets, sem quebrar em duas fileiras', (
      tester,
    ) async {
      await pumpSheet(tester, savings: FakeSavingsRepository());
      await openPercentage(tester);

      for (final preset in [10, 15, 20, 25, 30]) {
        expect(find.byKey(Key('goal_percentage_$preset')), findsOneWidget);
      }
      // Um sexto chip quebraria a fileira, e fileira quebrada lê como bug.
      expect(find.byKey(const Key('goal_percentage_5')), findsNothing);

      final chips = [10, 15, 20, 25, 30]
          .map((p) => tester.getRect(find.byKey(Key('goal_percentage_$p'))))
          .toList();
      expect(chips.map((r) => r.top).toSet(), hasLength(1));
    });

    testWidgets('não mostra teclado numérico — percentual é grosso', (
      tester,
    ) async {
      await pumpSheet(tester, savings: FakeSavingsRepository());
      await openPercentage(tester);

      expect(find.text('VALOR-ALVO'), findsNothing);
      expect(find.byKey(const Key('goal_percentage_20')), findsOneWidget);
    });

    testWidgets('diz de onde vem a renda quando há receita lançada', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        savings: FakeSavingsRepository(),
        transactions: [
          testTransaction(
            minor: 540000,
            type: TransactionType.income,
            occurredAt: testNow,
          ),
        ],
      );
      await openPercentage(tester);

      final note = find.byKey(const Key('goal_income_note'));
      expect(note, findsOneWidget);
      expect(
        tester.widget<Text>(note).data,
        allOf(contains(r'R$ 5.400,00'), contains(r'R$ 1.080,00')),
      );
    });

    testWidgets('sem receita lançada, diz o que fazer em vez de mostrar zero', (
      tester,
    ) async {
      await pumpSheet(tester, savings: FakeSavingsRepository());
      await openPercentage(tester);

      final note = tester.widget<Text>(
        find.byKey(const Key('goal_income_note')),
      );
      expect(note.data, contains('Nenhuma receita lançada'));
      expect(note.data, contains('Lance seu salário'));
    });

    testWidgets('sugere o nome, porque o tipo já o determina', (tester) async {
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings);
      await openPercentage(tester);

      await tapVisible(tester, find.byKey(const Key('goal_percentage_25')));
      await tapVisible(tester, find.byKey(const Key('goal_form_save')));

      expect(savings.created.single.name, '25% da renda');
      expect(savings.created.single.percentage, 25);
      expect(savings.created.single.targetAmountMinor, isNull);
    });

    testWidgets('o nome digitado vence a sugestão', (tester) async {
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings);
      await openPercentage(tester);

      await tester.enterText(
        find.byKey(const Key('goal_name')),
        'Um quinto do salário',
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('goal_form_save')));

      expect(savings.created.single.name, 'Um quinto do salário');
    });
  });

  group('edição', () {
    testWidgets('entra direto nos detalhes — o tipo é identidade', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        savings: FakeSavingsRepository(),
        editing: testGoal(),
      );

      expect(find.text('Editar meta'), findsOneWidget);
      expect(find.text('QUE TIPO DE META?'), findsNothing);
      expect(find.byKey(const Key('goal_form_back')), findsNothing);
    });

    testWidgets('salva as mudanças da meta', (tester) async {
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings, editing: testGoal());

      await tester.enterText(
        find.byKey(const Key('goal_name')),
        'Viagem ao Peru',
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('goal_form_save')));

      expect(savings.updated.single.name, 'Viagem ao Peru');
      expect(savings.updated.single.id, 'goal-1');
    });

    testWidgets('excluir pede confirmação antes', (tester) async {
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings, editing: testGoal());

      await tapVisible(tester, find.byKey(const Key('goal_form_remove')));

      expect(find.text('Excluir esta meta?'), findsOneWidget);
      expect(savings.deletedGoals, isEmpty);

      await tapVisible(tester, find.byKey(const Key('goal_remove_confirm')));

      expect(savings.deletedGoals, ['goal-1']);
    });

    testWidgets('cancelar a confirmação não exclui', (tester) async {
      final savings = FakeSavingsRepository();
      await pumpSheet(tester, savings: savings, editing: testGoal());

      await tapVisible(tester, find.byKey(const Key('goal_form_remove')));
      await tapVisible(tester, find.text('Cancelar'));

      expect(savings.deletedGoals, isEmpty);
    });

    testWidgets('falha de escrita aparece na folha, sem fechá-la', (
      tester,
    ) async {
      final savings = FakeSavingsRepository()
        ..writeFailure = const DatabaseFailure('Não foi possível salvar.');
      await pumpSheet(tester, savings: savings, editing: testGoal());

      await tapVisible(tester, find.byKey(const Key('goal_form_save')));

      expect(find.byKey(const Key('goal_form_error')), findsOneWidget);
      expect(find.text('Não foi possível salvar.'), findsOneWidget);
      expect(find.byKey(const Key('goal_form_save')), findsOneWidget);
    });
  });
}
