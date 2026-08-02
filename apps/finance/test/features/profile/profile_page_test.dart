import 'package:core/core.dart';
import 'package:finance/features/profile/domain/profile.dart';
import 'package:finance/features/profile/presentation/profile_name_sheet.dart';
import 'package:finance/features/profile/presentation/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// A seção "Você" do Perfil — o único lugar onde o nome é definido.
void main() {
  Future<FakeProfileRepository> pumpProfile(
    WidgetTester tester, {
    Profile? profile = const Profile(id: 'user-1'),
    FakeProfileRepository? repository,
  }) async {
    final repo = repository ?? FakeProfileRepository(profile: profile);
    await pumpScreen(tester, const ProfilePage(), profileRepository: repo);
    return repo;
  }

  group('a linha "Você"', () {
    testWidgets('sem nome, convida a definir em vez de ficar muda', (
      tester,
    ) async {
      await pumpProfile(tester);

      expect(find.text('Você'), findsOneWidget);
      expect(find.text('Defina seu nome'), findsOneWidget);
      expect(
        find.textContaining('quem divide um espaço com você vê só o seu papel'),
        findsOneWidget,
      );
    });

    testWidgets('com nome, mostra o nome e para que ele serve', (tester) async {
      await pumpProfile(
        tester,
        profile: const Profile(id: 'user-1', displayName: 'Giovanni'),
      );

      expect(find.text('Giovanni'), findsOneWidget);
      expect(find.text('Defina seu nome'), findsNothing);
      expect(
        find.textContaining('É assim que você aparece'),
        findsOneWidget,
      );
    });

    // Um `UPDATE` sem linha afeta zero e não dá erro. Deixar a linha tocável
    // aqui terminaria em "salvo" com nada salvo.
    testWidgets('perfil ainda não sincronizado não é tocável', (tester) async {
      await pumpProfile(tester, profile: null);

      expect(find.byKey(const Key('profile_you_skeleton')), findsOneWidget);
      expect(find.byKey(const Key('profile_you_tile')), findsNothing);
    });

    testWidgets('a seção fica acima de Contas', (tester) async {
      await pumpProfile(tester);

      final you = tester.getTopLeft(find.text('Você')).dy;
      final accounts = tester.getTopLeft(find.text('Contas')).dy;

      expect(you, lessThan(accounts));
    });
  });

  group('o sheet de nome', () {
    testWidgets('tocar na linha abre o sheet', (tester) async {
      await pumpProfile(tester);

      await tapVisible(tester, find.byKey(const Key('profile_you_tile')));

      expect(find.byType(ProfileNameSheet), findsOneWidget);
      expect(find.byKey(const Key('profile_name_field')), findsOneWidget);
    });

    testWidgets('o campo abre com o nome atual', (tester) async {
      await pumpProfile(
        tester,
        profile: const Profile(id: 'user-1', displayName: 'Giovanni'),
      );

      await tapVisible(tester, find.byKey(const Key('profile_you_tile')));

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('profile_name_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller?.text, 'Giovanni');
    });

    testWidgets('salvar grava o nome e fecha', (tester) async {
      final repo = await pumpProfile(tester);

      await tapVisible(tester, find.byKey(const Key('profile_you_tile')));
      await tester.enterText(
        find.byKey(const Key('profile_name_field')),
        'Giovanni',
      );
      await tapVisible(tester, find.byKey(const Key('profile_name_save')));

      expect(repo.saved, ['Giovanni']);
      expect(find.byType(ProfileNameSheet), findsNothing);
    });

    testWidgets('o nome novo aparece na linha sem recarregar a tela', (
      tester,
    ) async {
      await pumpProfile(tester);

      await tapVisible(tester, find.byKey(const Key('profile_you_tile')));
      await tester.enterText(
        find.byKey(const Key('profile_name_field')),
        'Giovanni',
      );
      await tapVisible(tester, find.byKey(const Key('profile_name_save')));

      expect(find.text('Giovanni'), findsOneWidget);
      expect(find.text('Defina seu nome'), findsNothing);
    });

    testWidgets('nome vazio é recusado e o sheet não fecha', (tester) async {
      await pumpProfile(tester);

      await tapVisible(tester, find.byKey(const Key('profile_you_tile')));
      await tapVisible(tester, find.byKey(const Key('profile_name_save')));

      expect(find.byType(ProfileNameSheet), findsOneWidget);
      expect(find.byKey(const Key('profile_name_error')), findsOneWidget);
      expect(find.text('Digite um nome.'), findsOneWidget);
    });

    testWidgets('nome só de espaços é recusado', (tester) async {
      final repo = await pumpProfile(tester);

      await tapVisible(tester, find.byKey(const Key('profile_you_tile')));
      await tester.enterText(
        find.byKey(const Key('profile_name_field')),
        '     ',
      );
      await tapVisible(tester, find.byKey(const Key('profile_name_save')));

      expect(repo.saved, ['     ']);
      expect(find.byType(ProfileNameSheet), findsOneWidget);
      expect(find.byKey(const Key('profile_name_error')), findsOneWidget);
    });

    testWidgets('o campo corta em 120 caracteres na digitação', (tester) async {
      final repo = await pumpProfile(tester);

      await tapVisible(tester, find.byKey(const Key('profile_you_tile')));
      await tester.enterText(
        find.byKey(const Key('profile_name_field')),
        'a' * 200,
      );
      await tapVisible(tester, find.byKey(const Key('profile_name_save')));

      expect(repo.saved.single.length, 120);
    });

    testWidgets('falha do repositório aparece na folha, sem fechar', (
      tester,
    ) async {
      final repo = FakeProfileRepository()
        ..failure = const DatabaseFailure(
          'Seu perfil ainda está sincronizando.',
        );
      await pumpProfile(tester, repository: repo);

      await tapVisible(tester, find.byKey(const Key('profile_you_tile')));
      await tester.enterText(
        find.byKey(const Key('profile_name_field')),
        'Giovanni',
      );
      await tapVisible(tester, find.byKey(const Key('profile_name_save')));

      expect(find.byType(ProfileNameSheet), findsOneWidget);
      expect(find.text('Seu perfil ainda está sincronizando.'), findsOneWidget);
    });
  });
}
