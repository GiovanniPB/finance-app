import 'package:core/core.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/space_member.dart';
import 'package:finance/features/spaces/presentation/space_detail_page.dart';
import 'package:finance/features/spaces/presentation/spaces_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  const owner = 'user-1';
  const guest = 'user-2';

  FakeSpacesRepository repositoryWith({
    Space? space,
    List<SpaceMember>? members,
    Failure? failure,
  }) {
    final shared = space ?? testSharedSpace();
    return FakeSpacesRepository(
      [personalSpace(), shared],
      members:
          members ??
          [
            // A linha do dono sai do `ownerId` do próprio espaço, e não de uma
            // constante igual por coincidência: é o que garante que ela
            // continue sendo a linha do dono se a fábrica mudar.
            testMember(id: 'm-dono', userId: shared.ownerId),
            testMember(
              id: 'm-convidado',
              userId: guest,
              role: SpaceRole.editor,
            ),
          ],
      failure: failure,
    );
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    FakeSpacesRepository? repository,
    String? currentUserId = owner,
  }) => pumpScreen(
    tester,
    const SpaceDetailPage(spaceId: 'space-2'),
    spacesRepository: repository ?? repositoryWith(),
    currentUserId: currentUserId,
    wrapInScaffold: false,
  );

  group('lista de espaços', () {
    testWidgets('tocar num espaço abre a tela dele, sem trocar de contexto', (
      tester,
    ) async {
      // A inversão desta fatia: abrir e passar a usar deixaram de ser o mesmo
      // gesto. Antes, tocar trocava o espaço ativo e a gestão ficava escondida
      // atrás de um ícone.
      await pumpScreen(
        tester,
        const SpacesPage(),
        spacesRepository: repositoryWith(),
      );

      await tapVisible(tester, find.byKey(const Key('space_open_space-2')));

      expect(find.byType(SpaceDetailPage), findsOneWidget);
    });

    testWidgets('o círculo à direita é o que troca de espaço', (tester) async {
      await pumpScreen(
        tester,
        const SpacesPage(),
        spacesRepository: repositoryWith(),
      );

      // O ativo não oferece o controle de novo — ele vira só a marca.
      final active = tester.widget<IconButton>(
        find.byKey(const Key('space_use_space-1')),
      );
      expect(active.onPressed, isNull);

      await tapVisible(tester, find.byKey(const Key('space_use_space-2')));

      expect(find.byType(SpaceDetailPage), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('space_use_space-2')))
            .onPressed,
        isNull,
      );
    });
  });

  group('resumo do espaço', () {
    testWidgets('conta as pessoas e diz o que o tipo significa', (
      tester,
    ) async {
      await pumpDetail(tester);

      expect(find.byKey(const Key('space_people_count')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // O rótulo "Grupo" não diz nada sozinho; a consequência de privacidade é
      // o conteúdo, e é ela que justifica o tipo ser imutável.
      expect(find.textContaining('só o que foi lançado aqui'), findsOneWidget);
    });

    testWidgets('espaço arquivado avisa, e some o que não dá mais para fazer', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        repository: repositoryWith(
          space: testSharedSpace().copyWith(status: SpaceStatus.archived),
        ),
      );

      expect(find.byKey(const Key('space_archived_banner')), findsOneWidget);
      expect(find.byKey(const Key('space_invite_generate')), findsNothing);
      expect(find.byKey(const Key('space_rename')), findsNothing);
      expect(find.byKey(const Key('space_archive')), findsNothing);
    });
  });

  group('quem está aqui', () {
    testWidgets('a linha diz o papel e o que ele permite', (tester) async {
      await pumpDetail(tester);

      expect(find.textContaining('Editor · Lança e edita'), findsOneWidget);
      expect(find.text('Você, que criou o espaço'), findsOneWidget);
    });

    testWidgets('sem nome de pessoa, a data de entrada distingue as linhas', (
      tester,
    ) async {
      // `profiles.display_name` não sincroniza para outros membros ainda. Um
      // uuid não identifica ninguém; a data, sim.
      await pumpDetail(tester);

      expect(find.textContaining('No espaço desde'), findsOneWidget);
    });

    testWidgets('admin abre as ações do membro; convidado não', (tester) async {
      await pumpDetail(tester);
      await tapVisible(tester, find.byKey(const Key('member_m-convidado')));

      expect(find.byKey(const Key('member_role_viewer')), findsOneWidget);
      expect(find.byKey(const Key('member_remove')), findsOneWidget);
    });

    testWidgets('a linha de quem criou não abre ação nenhuma', (tester) async {
      await pumpDetail(tester);

      final row = tester.widget<InkWell>(
        find.byKey(const Key('member_m-dono')),
      );
      expect(row.onTap, isNull);
    });

    testWidgets('editor não vê gestão de ninguém', (tester) async {
      await pumpDetail(tester, currentUserId: guest);

      for (final id in ['m-dono', 'm-convidado']) {
        expect(
          tester.widget<InkWell>(find.byKey(Key('member_$id'))).onTap,
          isNull,
        );
      }
      expect(find.byKey(const Key('space_invite_generate')), findsNothing);
    });
  });

  group('trocar papel', () {
    testWidgets('manda o papel escolhido e fecha a folha', (tester) async {
      final repository = repositoryWith();
      await pumpDetail(tester, repository: repository);

      await tapVisible(tester, find.byKey(const Key('member_m-convidado')));
      await tapVisible(tester, find.byKey(const Key('member_role_viewer')));

      expect(repository.roleChanges, hasLength(1));
      expect(repository.roleChanges.single.memberId, 'm-convidado');
      expect(repository.roleChanges.single.role, SpaceRole.viewer);
    });

    testWidgets('o papel atual não é tocável — não há o que aplicar', (
      tester,
    ) async {
      await pumpDetail(tester);
      await tapVisible(tester, find.byKey(const Key('member_m-convidado')));

      final current = tester.widget<InkWell>(
        find.byKey(const Key('member_role_editor')),
      );
      expect(current.onTap, isNull);
    });
  });

  group('remover membro', () {
    testWidgets('pede confirmação, e a confirmação diz o que fica', (
      tester,
    ) async {
      final repository = repositoryWith();
      await pumpDetail(tester, repository: repository);

      await tapVisible(tester, find.byKey(const Key('member_m-convidado')));
      await tapVisible(tester, find.byKey(const Key('member_remove')));

      // Sem esta frase é razoável temer que remover apague o que a pessoa
      // lançou — que é justamente o que **não** acontece.
      expect(find.textContaining('O que ela lançou continua'), findsOneWidget);
      expect(repository.removed, isEmpty);

      await tapVisible(tester, find.byKey(const Key('member_remove_confirm')));

      expect(repository.removed, ['m-convidado']);
    });

    testWidgets('falha aparece na folha, sem fechá-la', (tester) async {
      await pumpDetail(
        tester,
        repository: repositoryWith(
          failure: const ValidationFailure('Quem criou o espaço é admin.'),
        ),
      );

      await tapVisible(tester, find.byKey(const Key('member_m-convidado')));
      await tapVisible(tester, find.byKey(const Key('member_remove')));
      await tapVisible(tester, find.byKey(const Key('member_remove_confirm')));

      expect(find.byKey(const Key('member_action_error')), findsOneWidget);
      expect(find.text('Quem criou o espaço é admin.'), findsOneWidget);
    });
  });

  group('sair e arquivar', () {
    testWidgets('quem criou não vê "sair", e a tela explica por quê', (
      tester,
    ) async {
      await pumpDetail(tester);

      expect(find.byKey(const Key('space_leave')), findsNothing);
      expect(find.byKey(const Key('space_cannot_leave')), findsOneWidget);
      expect(find.byKey(const Key('space_archive')), findsOneWidget);
    });

    testWidgets('convidado vê "sair" e não vê "arquivar"', (tester) async {
      await pumpDetail(tester, currentUserId: guest);

      expect(find.byKey(const Key('space_leave')), findsOneWidget);
      expect(find.byKey(const Key('space_archive')), findsNothing);
    });

    testWidgets('sair pede confirmação antes de sair', (tester) async {
      final repository = repositoryWith();
      await pumpDetail(
        tester,
        repository: repository,
        currentUserId: guest,
      );

      await tapVisible(tester, find.byKey(const Key('space_leave')));
      expect(repository.left, isEmpty);

      await tapVisible(tester, find.byKey(const Key('space_leave_confirm')));
      expect(repository.left, ['space-2']);
    });

    testWidgets('arquivar pede confirmação e diz que não apaga nada', (
      tester,
    ) async {
      final repository = repositoryWith();
      await pumpDetail(tester, repository: repository);

      await tapVisible(tester, find.byKey(const Key('space_archive')));
      expect(find.textContaining('Não apaga nada'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('space_archive_confirm')));
      expect(repository.archived, ['space-2']);
    });
  });

  group('espaço pessoal', () {
    testWidgets('abre com resumo, e sem nada de membro ou convite', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SpaceDetailPage(spaceId: 'space-1'),
        spacesRepository: repositoryWith(),
        wrapInScaffold: false,
      );

      expect(find.text('Quem está aqui'), findsNothing);
      expect(find.byKey(const Key('space_invite_generate')), findsNothing);
      expect(find.byKey(const Key('space_leave')), findsNothing);
      expect(find.textContaining('Só você'), findsOneWidget);
    });
  });

  group('espaço ausente do banco local', () {
    testWidgets('antes de sincronizar mostra progresso, não "você saiu"', (
      tester,
    ) async {
      // Os dois estados chegam como o mesmo `null`, e confundi-los daria a
      // pior das duas telas: "você não está mais neste espaço" durante o boot.
      // É o que o `_hasSeenSpace` da página existe para separar.
      await pumpScreen(
        tester,
        const SpaceDetailPage(spaceId: 'space-inexistente'),
        spacesRepository: repositoryWith(),
        wrapInScaffold: false,
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Você não está mais neste espaço'), findsNothing);
    });
  });

  group('renomear', () {
    testWidgets('salva o nome novo', (tester) async {
      final repository = repositoryWith();
      await pumpDetail(tester, repository: repository);

      await tapVisible(tester, find.byKey(const Key('space_rename')));
      await tester.enterText(
        find.byKey(const Key('space_rename_name')),
        'República',
      );
      await tapVisible(tester, find.byKey(const Key('space_rename_save')));

      expect(repository.renamed, ['República']);
    });
  });
}
