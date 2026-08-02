import 'package:core/core.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/space_member.dart';
import 'package:finance/features/spaces/presentation/space_detail_page.dart';
import 'package:finance/features/transactions/domain/settlement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// A seção "Acertar contas" no detalhe do espaço.
///
/// O que se prova aqui é o que se lê sem olhar: qual frase aparece em cada
/// vazio, quem tem ação e quem não tem, e o que o toque registra. A aparência —
/// peso, cor, espaçamento — não tem degrau automático neste projeto (ver
/// `AGENTS.md`), e termina no usuário olhando a tela.
void main() {
  const owner = 'user-1';
  const guest = 'user-2';
  const third = 'user-3';

  MemberBalance balance(String userId, int minor) =>
      MemberBalance(userId: userId, net: Money.fromMinor(minor));

  FakeSpacesRepository spacesWith({Space? space, List<SpaceMember>? members}) {
    final shared = space ?? testSharedSpace();
    return FakeSpacesRepository(
      [personalSpace(), shared],
      members:
          members ??
          [
            testMember(id: 'm-dono', userId: shared.ownerId),
            testMember(
              id: 'm-convidado',
              userId: guest,
              role: SpaceRole.editor,
              displayName: 'Ana Prado',
            ),
          ],
    );
  }

  Future<FakeSettlementRepository> pumpDetail(
    WidgetTester tester, {
    FakeSettlementRepository? settlement,
    FakeSpacesRepository? spaces,
    String spaceId = 'space-2',
    String? currentUserId = owner,
  }) async {
    final repository = settlement ?? FakeSettlementRepository();
    await pumpScreen(
      tester,
      SpaceDetailPage(spaceId: spaceId),
      spacesRepository: spaces ?? spacesWith(),
      settlementRepository: repository,
      currentUserId: currentUserId,
      wrapInScaffold: false,
    );
    return repository;
  }

  group('onde a seção não aparece', () {
    // `household` liquida de outro jeito por desenho (PRD §4.2) e `personal`
    // não tem com quem acertar. Nos dois a seção **não existe**, em vez de
    // existir vazia — mesma regra de "Dividido entre".
    testWidgets('espaço pessoal', (tester) async {
      await pumpDetail(tester, spaceId: 'space-1');

      expect(find.text('Acertar contas'), findsNothing);
    });

    testWidgets('household', (tester) async {
      final household = testSharedSpace().copyWith(type: SpaceType.household);
      await pumpDetail(tester, spaces: spacesWith(space: household));

      expect(find.text('Acertar contas'), findsNothing);
    });
  });

  group('os três vazios dizem coisas diferentes', () {
    testWidgets('sem despesa dividida, ensina onde dividir', (tester) async {
      await pumpDetail(tester);

      expect(find.byKey(const Key('settlement_nothing_split')), findsOneWidget);
      expect(find.textContaining('Dividir igualmente'), findsOneWidget);
    });

    testWidgets('tudo quite é resultado, não lista de zeros', (tester) async {
      await pumpDetail(
        tester,
        settlement: FakeSettlementRepository(
          balances: [balance(owner, 0), balance(guest, 0)],
          splitCount: 4,
        ),
      );

      expect(find.byKey(const Key('settlement_all_settled')), findsOneWidget);
      expect(find.text('Está tudo quite.'), findsOneWidget);
      // Nenhum valor dentro da seção: quite é uma frase, não uma coluna de
      // zeros. (O cartão de resumo do espaço, acima, tem valores próprios — por
      // isso a busca é dentro do vazio, e não na tela.)
      expect(
        find.descendant(
          of: find.byKey(const Key('settlement_all_settled')),
          matching: find.textContaining(r'R$'),
        ),
        findsNothing,
      );
    });

    testWidgets('moeda divergente recusa somar', (tester) async {
      await pumpDetail(
        tester,
        settlement: FakeSettlementRepository(
          balances: [
            const MemberBalance(userId: owner, net: Money.fromMinor(5000)),
            const MemberBalance(
              userId: guest,
              net: Money.fromMinor(-5000, currency: 'USD'),
            ),
          ],
          splitCount: 2,
        ),
      );

      expect(
        find.byKey(const Key('settlement_mixed_currency')),
        findsOneWidget,
      );
    });
  });

  group('com saldo', () {
    FakeSettlementRepository owed() => FakeSettlementRepository(
      // O dono adiantou R$ 160 de um mercado de R$ 240 entre três.
      balances: [
        balance(owner, 16000),
        balance(guest, -8000),
        balance(third, -8000),
      ],
      splitCount: 1,
    );

    testWidgets('a faixa responde "e eu?" antes da lista', (tester) async {
      await pumpDetail(tester, settlement: owed());

      expect(find.text('Você tem a receber'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('settlement_my_position')),
                matching: find.byType(Text),
                matchRoot: true,
              ),
            )
            .data,
        r'+R$ 160,00',
      );
    });

    testWidgets('quem deve vê "Você deve", sem sinal e sem cor', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        settlement: owed(),
        currentUserId: guest,
      );

      expect(find.text('Você deve'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('settlement_my_position')),
                matching: find.byType(Text),
                matchRoot: true,
              ),
            )
            .data,
        r'R$ 80,00',
      );
    });

    testWidgets('uma linha por transferência, com o nome de cada ponta', (
      tester,
    ) async {
      await pumpDetail(tester, settlement: owed());

      expect(find.byKey(const Key('transfer_user-2_user-1')), findsOneWidget);
      expect(find.byKey(const Key('transfer_user-3_user-1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('transfer_user-2_user-1')),
          matching: find.textContaining('Ana Prado', findRichText: true),
        ),
        findsOneWidget,
      );
    });

    // Quem nunca abriu o Perfil não tem nome, e o fallback da lista de membros
    // ("No espaço desde 28 de julho") não cabe numa linha com duas pessoas.
    testWidgets('sem nome, cai em "Membro sem nome"', (tester) async {
      await pumpDetail(tester, settlement: owed());

      expect(
        find.descendant(
          of: find.byKey(const Key('transfer_user-3_user-1')),
          matching: find.textContaining('Membro sem nome', findRichText: true),
        ),
        findsOneWidget,
      );
    });

    testWidgets('o rodapé conta as transferências e as despesas', (
      tester,
    ) async {
      await pumpDetail(tester, settlement: owed());

      expect(find.text('2 transferências zeram o grupo'), findsOneWidget);
      expect(find.text('1 despesa dividida'), findsOneWidget);
      expect(find.byKey(const Key('settlement_hint')), findsOneWidget);
    });
  });

  group('registrar o acerto', () {
    FakeSettlementRepository twoWay() => FakeSettlementRepository(
      balances: [
        balance(owner, 16000),
        balance(guest, -8000),
        balance(third, -8000),
      ],
      splitCount: 1,
    );

    testWidgets('a linha que não me envolve não tem ação', (tester) async {
      // Pelos olhos de quem não está em transferência nenhuma: as duas linhas
      // são informativas. Acertar dívida de terceiros exigiria responder quem
      // tem direito de declarar pagamento alheio.
      await pumpDetail(
        tester,
        settlement: FakeSettlementRepository(
          balances: [
            balance(owner, 0),
            balance(guest, 8000),
            balance(third, -8000),
          ],
          splitCount: 1,
        ),
      );

      await tester.tap(find.byKey(const Key('transfer_user-3_user-2')));
      await tester.pumpAndSettle();

      expect(find.text('Registrar'), findsNothing);
    });

    testWidgets('tocar a minha linha pede confirmação antes de gravar', (
      tester,
    ) async {
      final repository = await pumpDetail(tester, settlement: twoWay());

      await tapVisible(
        tester,
        find.byKey(const Key('transfer_user-2_user-1')),
      );

      // O texto diz o que vai ser gravado: o acerto cria um lançamento no
      // grupo, e ninguém espera que "já paguei" apareça na lista do mês.
      expect(find.textContaining('Ana Prado te pagou?'), findsOneWidget);
      expect(
        find.textContaining('Registra uma transferência'),
        findsOneWidget,
      );
      expect(repository.settled, isEmpty);
    });

    testWidgets('cancelar não grava nada', (tester) async {
      final repository = await pumpDetail(tester, settlement: twoWay());

      await tapVisible(
        tester,
        find.byKey(const Key('transfer_user-2_user-1')),
      );
      await tapVisible(tester, find.text('Cancelar'));

      expect(repository.settled, isEmpty);
    });

    testWidgets('confirmar registra o acerto com as duas pontas', (
      tester,
    ) async {
      final repository = await pumpDetail(tester, settlement: twoWay());

      await tapVisible(
        tester,
        find.byKey(const Key('transfer_user-2_user-1')),
      );
      await tapVisible(tester, find.byKey(const Key('confirm_settle')));

      expect(repository.settled, hasLength(1));
      expect(repository.settled.single.from, guest);
      expect(repository.settled.single.to, owner);
      expect(repository.settled.single.amount, const Money.fromMinor(8000));
    });

    testWidgets('a falha aparece na linha, e não em silêncio', (tester) async {
      final repository = twoWay()..failure = const DatabaseFailure('Deu ruim.');
      await pumpDetail(tester, settlement: repository);

      await tapVisible(
        tester,
        find.byKey(const Key('transfer_user-2_user-1')),
      );
      await tapVisible(tester, find.byKey(const Key('confirm_settle')));

      expect(find.byKey(const Key('settlement_error')), findsOneWidget);
      expect(find.text('Deu ruim.'), findsOneWidget);
    });
  });
}
