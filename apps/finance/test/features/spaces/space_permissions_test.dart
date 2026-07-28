import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/space_member.dart';
import 'package:finance/features/spaces/domain/space_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// As invariantes de permissão, do lado do cliente.
///
/// Elas existem em dois lugares — aqui e na migration `20260728210321`, em
/// policy e trigger. A duplicação é deliberada e está explicada em
/// [SpacePermissions]: escrita recusada pela RLS **não** vira erro na tela num
/// app offline-first, ela aparece aplicada e some no checkpoint seguinte. Se um
/// destes testes mudar sem a migration mudar junto, um dos dois lados está
/// mentindo.
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

  group('quem criou o espaço', () {
    test('é sempre admin: ninguém troca o papel dele', () {
      // Sem isto, um admin toma o espaço de quem o criou — e era exatamente o
      // que o banco permitia antes da migration 20260728210321.
      final permissions = permissionsFor();
      final ownerRow = testMember(id: 'm-dono', userId: owner);

      expect(permissions.canChangeRoleOf(ownerRow), isFalse);
      expect(permissions.canRemove(ownerRow), isFalse);
    });

    test('não sai: encerrar é arquivar', () {
      final permissions = permissionsFor();

      expect(permissions.canLeave, isFalse);
      expect(permissions.whyCannotLeave, contains('arquive'));
      expect(permissions.canArchive, isTrue);
    });
  });

  group('quem não é admin', () {
    test('não convida, não renomeia, não arquiva, não mexe em membro', () {
      final permissions = permissionsFor(
        userId: guest,
        role: SpaceRole.editor,
      );

      expect(permissions.canInvite, isFalse);
      expect(permissions.canRename, isFalse);
      expect(permissions.canArchive, isFalse);
      expect(permissions.canManageMembers, isFalse);
    });

    test('mas sai quando quiser', () {
      final permissions = permissionsFor(
        userId: guest,
        role: SpaceRole.viewer,
      );

      expect(permissions.canLeave, isTrue);
      expect(permissions.whyCannotLeave, isNull);
    });
  });

  group('papel ainda não sincronizado', () {
    test('não pode nada — nulo é "não", não "talvez"', () {
      // Prometer uma permissão que o servidor vai recusar é pior do que
      // esconder o controle até saber.
      final permissions = permissionsFor(userId: guest, role: null);

      expect(permissions.canInvite, isFalse);
      expect(permissions.canManageMembers, isFalse);
      expect(permissions.canLeave, isFalse);
    });
  });

  group('espaço arquivado', () {
    final archived = testSharedSpace().copyWith(status: SpaceStatus.archived);

    test('não recebe convite, nome novo nem gestão de membro', () {
      final permissions = permissionsFor(space: archived);

      expect(permissions.canInvite, isFalse);
      expect(permissions.canRename, isFalse);
      expect(permissions.canArchive, isFalse);
      expect(permissions.canManageMembers, isFalse);
    });

    test('mas ainda dá para sair — é onde faz sentido limpar', () {
      final permissions = permissionsFor(
        userId: guest,
        role: SpaceRole.editor,
        space: archived,
      );

      expect(permissions.canLeave, isTrue);
    });
  });

  group('espaço pessoal', () {
    final personal = personalSpace();

    test('não convida, não arquiva e não tem de onde sair', () {
      final permissions = permissionsFor(space: personal);

      expect(permissions.canInvite, isFalse);
      expect(permissions.canArchive, isFalse);
      expect(permissions.canLeave, isFalse);
      // E não há frase de "por que não": não há saída porque não há grupo.
      expect(permissions.whyCannotLeave, isNull);
    });

    test('mas renomeia: é um espaço como os outros', () {
      expect(permissionsFor(space: personal).canRename, isTrue);
    });
  });

  group('admin sobre si mesmo', () {
    test('não se remove — para isso existe sair', () {
      // As duas ações têm consequências diferentes para quem fica, e frases
      // diferentes. Fundi-las esconderia uma das duas.
      final permissions = permissionsFor(
        userId: guest,
        role: SpaceRole.admin,
      );
      final myRow = testMember(id: 'm-eu', userId: guest);

      expect(permissions.canRemove(myRow), isFalse);
      expect(permissions.canLeave, isTrue);
    });

    test('pode se rebaixar: o espaço não fica sem admin, o dono é um', () {
      final permissions = permissionsFor(
        userId: guest,
        role: SpaceRole.admin,
      );

      expect(
        permissions.canChangeRoleOf(testMember(id: 'm-eu', userId: guest)),
        isTrue,
      );
    });
  });
}
