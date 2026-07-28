import 'package:core/core.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/presentation/join_space_sheet.dart';
import 'package:finance/features/spaces/presentation/space_form_sheet.dart';
import 'package:finance/features/spaces/presentation/spaces_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  group('tela de espaços', () {
    testWidgets('oferece criar e entrar com código lado a lado', (
      tester,
    ) async {
      // A segunda ação não é óbvia e é a que o convidado precisa: sem um
      // caminho próprio, quem recebeu um código não teria onde colá-lo.
      await pumpScreen(
        tester,
        const SpacesPage(),
        spacesRepository: FakeSpacesRepository([personalSpace()]),
      );

      expect(find.byKey(const Key('space_new')), findsOneWidget);
      expect(find.byKey(const Key('space_join')), findsOneWidget);
    });

    testWidgets('sem espaço compartilhado, convida a criar o primeiro', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SpacesPage(),
        spacesRepository: FakeSpacesRepository([personalSpace()]),
      );

      expect(find.text('Dividir ou somar com alguém'), findsOneWidget);
    });

    testWidgets('com um grupo, o convite a criar sai da frente', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SpacesPage(),
        spacesRepository: FakeSpacesRepository([
          personalSpace(),
          testSharedSpace(),
        ]),
      );

      expect(find.text('Dividir ou somar com alguém'), findsNothing);
      expect(find.text('Viagem ao Chile'), findsOneWidget);
    });

    testWidgets('toda linha abre e toda linha pode virar a ativa', (
      tester,
    ) async {
      // Inclusive o Pessoal: ele tem resumo e nome, mesmo sem membro para
      // gerenciar — e uma linha que não responde ao toque, no meio de outras
      // que respondem, lê como bug.
      await pumpScreen(
        tester,
        const SpacesPage(),
        spacesRepository: FakeSpacesRepository([
          personalSpace(),
          testSharedSpace(),
        ]),
      );

      for (final id in ['space-1', 'space-2']) {
        expect(find.byKey(Key('space_open_$id')), findsOneWidget);
        expect(find.byKey(Key('space_use_$id')), findsOneWidget);
      }
    });
  });

  group('novo espaço', () {
    testWidgets('cada tipo diz a consequência, não só o nome', (tester) async {
      // "Grupo" e "Casal" não dizem que um divide despesa e o outro abre tudo.
      await pumpScreen(tester, const SpaceFormSheet());

      expect(find.textContaining('quem deve a quem'), findsOneWidget);
      expect(find.textContaining('visível para os dois'), findsOneWidget);
    });

    testWidgets('cria um grupo com o nome digitado', (tester) async {
      final repo = FakeSpacesRepository([personalSpace()]);
      await pumpScreen(tester, const SpaceFormSheet(), spacesRepository: repo);

      await tester.enterText(find.byKey(const Key('space_name')), 'República');
      await tapVisible(tester, find.byKey(const Key('space_form_save')));

      expect(repo.created, hasLength(1));
      expect(repo.created.single.name, 'República');
      expect(repo.created.single.type, SpaceType.group);
    });

    testWidgets('escolher casal grava household', (tester) async {
      final repo = FakeSpacesRepository([personalSpace()]);
      await pumpScreen(tester, const SpaceFormSheet(), spacesRepository: repo);

      await tester.enterText(find.byKey(const Key('space_name')), 'Casa');
      await tapVisible(tester, find.byKey(const Key('space_type_household')));
      await tapVisible(tester, find.byKey(const Key('space_form_save')));

      expect(repo.created.single.type, SpaceType.household);
      // A política vem do tipo, nunca é perguntada: household sem
      // transparência é um tipo que não existe.
      expect(repo.created.single.privacy, SpacePrivacy.fullTransparency);
    });

    testWidgets('falha aparece na folha, sem fechá-la', (tester) async {
      await pumpScreen(
        tester,
        const SpaceFormSheet(),
        spacesRepository: FakeSpacesRepository(
          [personalSpace()],
          failure: const ValidationFailure('Dê um nome para o espaço.'),
        ),
      );

      await tapVisible(tester, find.byKey(const Key('space_form_save')));

      expect(find.byKey(const Key('space_form_error')), findsOneWidget);
      expect(find.byKey(const Key('space_form_save')), findsOneWidget);
    });
  });

  group('entrar com código', () {
    testWidgets('manda o código digitado', (tester) async {
      final repo = FakeSpacesRepository([personalSpace()]);
      await pumpScreen(tester, const JoinSpaceSheet(), spacesRepository: repo);

      await tester.enterText(find.byKey(const Key('join_code')), 'WM38G4KA');
      await tapVisible(tester, find.byKey(const Key('join_submit')));

      expect(repo.joined, ['WM38G4KA']);
    });

    testWidgets('digitar minúsculo vira maiúsculo, não campo travado', (
      tester,
    ) async {
      // O filtro só aceita [A-Z2-9]; sem a conversão antes dele, digitar em
      // minúsculas não produziria caractere nenhum.
      final repo = FakeSpacesRepository([personalSpace()]);
      await pumpScreen(tester, const JoinSpaceSheet(), spacesRepository: repo);

      await tester.enterText(find.byKey(const Key('join_code')), 'wm38g4ka');
      await tapVisible(tester, find.byKey(const Key('join_submit')));

      expect(repo.joined, ['WM38G4KA']);
    });

    testWidgets('caractere fora do alfabeto do código não entra', (
      tester,
    ) async {
      // `O`, `I` e `0` nunca existiram num código: recusar na entrada é mais
      // honesto do que aceitar e depois dizer "inválido".
      final repo = FakeSpacesRepository([personalSpace()]);
      await pumpScreen(tester, const JoinSpaceSheet(), spacesRepository: repo);

      await tester.enterText(find.byKey(const Key('join_code')), 'WO0I1MA-');
      await tapVisible(tester, find.byKey(const Key('join_submit')));

      expect(repo.joined.single, 'WMA');
    });

    testWidgets('código recusado aparece na folha', (tester) async {
      await pumpScreen(
        tester,
        const JoinSpaceSheet(),
        spacesRepository: FakeSpacesRepository(
          [personalSpace()],
          failure: const ValidationFailure('Código inválido ou expirado'),
        ),
      );

      await tester.enterText(find.byKey(const Key('join_code')), 'ZZZZZZZZ');
      await tapVisible(tester, find.byKey(const Key('join_submit')));

      expect(find.text('Código inválido ou expirado'), findsOneWidget);
    });
  });
}
