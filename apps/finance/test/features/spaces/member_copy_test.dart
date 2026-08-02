import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/space_member.dart';
import 'package:finance/features/spaces/domain/space_permissions.dart';
import 'package:finance/features/spaces/presentation/member_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// As frases da linha de membro.
///
/// Metade destes testes existe para proteger o **fallback**: enquanto ninguém
/// definir nome, a lista tem de ficar idêntica à que existia antes da coluna
/// `display_name`. É o estado em que ela vai viver por semanas.
void main() {
  // `testSharedSpace()` nasce com `ownerId: 'user-1'`.
  const owner = 'user-1';
  const guest = 'user-2';

  SpacePermissions permissionsFor({
    String? userId = owner,
    SpaceRole? role = SpaceRole.admin,
    Space? space,
  }) => SpacePermissions(
    space: space ?? testSharedSpace(),
    myUserId: userId,
    myRole: role,
  );

  /// A linha de quem criou o espaço. `testMember` já nasce com `userId: owner`,
  /// então repetir o argumento seria redundante — este atalho deixa a intenção
  /// no nome em vez de num parâmetro.
  SpaceMember ownerMember({String id = 'member-1', String? displayName}) =>
      testMember(id: id, displayName: displayName);

  MemberIdentity identityOf(
    SpaceMember member, {
    SpacePermissions? permissions,
    String? myDisplayName,
  }) => MemberCopy.identity(
    member: member,
    permissions: permissions ?? permissionsFor(),
    today: testNow,
    myDisplayName: myDisplayName,
  );

  group('sem nome nenhum, as frases são as de antes da coluna', () {
    test('eu, que criei o espaço', () {
      final identity = identityOf(ownerMember());

      expect(identity.label, 'Você, que criou o espaço');
      expect(identity.qualifier, isNull);
    });

    test('eu, sem ser quem criou', () {
      final identity = identityOf(
        testMember(userId: guest),
        permissions: permissionsFor(userId: guest),
      );

      expect(identity.label, 'Você');
      expect(identity.qualifier, isNull);
    });

    test('quem criou o espaço, não sendo eu', () {
      final identity = identityOf(
        ownerMember(),
        permissions: permissionsFor(userId: guest),
      );

      expect(identity.label, 'Quem criou o espaço');
      expect(identity.qualifier, isNull);
    });

    test('outra pessoa cai na data de entrada', () {
      final identity = identityOf(testMember(userId: guest));

      expect(identity.label, startsWith('No espaço desde '));
      expect(identity.qualifier, isNull);
    });
  });

  group('com nome, o nome lidera e a data some', () {
    test('outra pessoa é só o nome', () {
      final identity = identityOf(
        testMember(userId: guest, displayName: 'Ana Prado'),
      );

      expect(identity.label, 'Ana Prado');
      expect(identity.qualifier, isNull);
      expect(identity.text, 'Ana Prado');
    });

    test('a data de entrada não aparece em lugar nenhum', () {
      final identity = identityOf(
        testMember(userId: guest, displayName: 'Ana Prado'),
      );

      expect(identity.text, isNot(contains('No espaço desde')));
    });

    test('eu, que criei o espaço', () {
      final identity = identityOf(
        ownerMember(displayName: 'Giovanni'),
      );

      expect(identity.label, 'Giovanni');
      expect(identity.qualifier, 'você, que criou o espaço');
      expect(identity.text, 'Giovanni · você, que criou o espaço');
    });

    test('eu, sem ser quem criou', () {
      final identity = identityOf(
        testMember(userId: guest, displayName: 'Ana Prado'),
        permissions: permissionsFor(userId: guest),
      );

      expect(identity.qualifier, 'você');
      expect(identity.text, 'Ana Prado · você');
    });

    test('quem criou o espaço, não sendo eu', () {
      final identity = identityOf(
        ownerMember(displayName: 'Giovanni'),
        permissions: permissionsFor(userId: guest),
      );

      expect(identity.qualifier, 'quem criou o espaço');
      expect(identity.text, 'Giovanni · quem criou o espaço');
    });
  });

  group('de onde vem o meu nome', () {
    // A razão de `myDisplayName` existir: entre eu salvar o nome no Perfil e o
    // trigger do Postgres propagar, a minha própria membership carrega o valor
    // velho. Sem esta precedência, eu trocaria o nome e veria o antigo.
    test('na minha linha, profiles vence a coluna copiada', () {
      final identity = identityOf(
        ownerMember(displayName: 'Nome velho'),
        myDisplayName: 'Nome novo',
      );

      expect(identity.label, 'Nome novo');
    });

    test('na minha linha, profiles vale mesmo com a cópia ainda nula', () {
      final identity = identityOf(
        ownerMember(),
        myDisplayName: 'Giovanni',
      );

      expect(identity.label, 'Giovanni');
      expect(identity.qualifier, 'você, que criou o espaço');
    });

    test('na linha do outro, o meu nome não vaza', () {
      final identity = identityOf(
        testMember(userId: guest),
        myDisplayName: 'Giovanni',
      );

      expect(identity.label, startsWith('No espaço desde '));
    });

    test('a cópia vale para a minha linha quando não há profiles ainda', () {
      final identity = identityOf(
        ownerMember(displayName: 'Da cópia'),
      );

      expect(identity.label, 'Da cópia');
    });
  });

  group('mistura — o caso que a lista vai viver por semanas', () {
    test('só eu com nome: a outra linha fica como antes', () {
      final mine = identityOf(
        ownerMember(id: 'm-1'),
        myDisplayName: 'Giovanni',
      );
      final theirs = identityOf(testMember(id: 'm-2', userId: guest));

      expect(mine.text, 'Giovanni · você, que criou o espaço');
      expect(theirs.text, startsWith('No espaço desde '));
    });

    test('dois membros com o mesmo nome seguem distinguíveis pelo papel', () {
      final a = testMember(
        id: 'm-1',
        userId: 'user-3',
        role: SpaceRole.editor,
        displayName: 'Ana',
      );
      final b = testMember(
        id: 'm-2',
        userId: 'user-4',
        role: SpaceRole.viewer,
        displayName: 'Ana',
      );

      expect(identityOf(a).text, identityOf(b).text);
      expect(MemberCopy.role(a.role), isNot(MemberCopy.role(b.role)));
    });
  });

  // O rótulo curto da linha de acerto. Existe porque o fallback de `identity`
  // é "No espaço desde 28 de julho", que numa transferência sairia como
  // *"No espaço desde 28 de julho → Você"*.
  group('shortIdentity', () {
    MemberIdentity shortOf(
      String userId, {
      List<SpaceMember>? members,
      SpacePermissions? permissions,
    }) => MemberCopy.shortIdentity(
      userId: userId,
      members: members ?? [ownerMember(), testMember(id: 'm-2', userId: guest)],
      permissions: permissions ?? permissionsFor(),
    );

    test('a minha ponta é sempre "Você", mesmo com nome definido', () {
      final identity = shortOf(
        owner,
        members: [
          ownerMember(displayName: 'Giovanni'),
          testMember(id: 'm-2', userId: guest),
        ],
      );

      expect(identity.label, 'Você');
      expect(identity.qualifier, isNull);
    });

    test('a outra ponta é o nome dela', () {
      final identity = shortOf(
        guest,
        members: [
          ownerMember(),
          testMember(id: 'm-2', userId: guest, displayName: 'Ana Prado'),
        ],
      );

      expect(identity.label, 'Ana Prado');
      expect(identity.qualifier, isNull);
    });

    test('sem nome, o rótulo curto pede o nome sem dizer', () {
      expect(shortOf(guest).label, 'Membro sem nome');
    });

    // A dívida não sai do espaço junto com a pessoa: quem saiu continua no
    // saldo, com o qualificador que explica por que aquele nome está ali.
    test('quem saiu ganha o qualificador', () {
      final identity = shortOf(
        guest,
        members: [
          ownerMember(),
          testMember(
            id: 'm-2',
            userId: guest,
            displayName: 'Ana Prado',
            status: MembershipStatus.left,
          ),
        ],
      );

      expect(identity.label, 'Ana Prado');
      expect(identity.qualifier, 'saiu do espaço');
    });

    test('sem membership nenhuma, ainda aparece', () {
      final identity = shortOf('user-3');

      expect(identity.label, 'Membro sem nome');
      expect(identity.qualifier, 'saiu do espaço');
    });
  });

  group('role', () {
    test('junta o papel ao que ele permite', () {
      expect(MemberCopy.role(SpaceRole.editor), 'Editor · Lança e edita');
      expect(MemberCopy.role(SpaceRole.viewer), 'Leitor · Só vê');
      expect(
        MemberCopy.role(SpaceRole.admin),
        'Admin · Convida, remove e edita tudo',
      );
    });
  });
}
