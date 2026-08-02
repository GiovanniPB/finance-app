import 'package:core/core.dart';
import 'package:finance/di/providers.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/domain/space_member.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import 'helpers/local_stack.dart';

/// A fatia `nome-de-membro` contra o PowerSync de verdade.
///
/// Existe por uma razão específica: o `UPDATE` de `profiles` e o `INSERT` de
/// `space_members` com a coluna nova passam por **views com triggers
/// `INSTEAD OF`**, e um mock de `SqliteConnection` não distingue SQL que o
/// SQLite aceita de SQL que ele recusa. Foi assim que o UPSERT de orçamento
/// ficou verde por meses estando quebrado.
///
/// O que **não** se prova aqui: a propagação para os peers. Ela mora em dois
/// triggers do Postgres (migration `20260801205317`) e exige o servidor — o
/// débito de "o upload ao Postgres não é testado automaticamente" continua
/// valendo, e é o mesmo de sempre.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Insere a linha de `profiles` direto no banco local.
  ///
  /// No app ela chega pelo bucket `user_owned`, criada no cadastro pelo
  /// trigger `handle_new_user`. Aqui não há sync, então entra pela porta dos
  /// fundos — como `seedSpace` faz com o espaço.
  Future<void> seedProfile(
    PowerSyncDatabase db, {
    String id = 'user-1',
    String? displayName,
  }) => db.execute(
    'INSERT INTO profiles (id, display_name, created_at, updated_at) '
    'VALUES (?, ?, ?, ?)',
    [
      id,
      displayName,
      '2026-07-01T00:00:00.000Z',
      '2026-07-01T00:00:00.000Z',
    ],
  );

  group('profiles: escrever o nome', () {
    test('o UPDATE atravessa a view e grava', () async {
      final stack = await localStack();
      await seedProfile(stack.db);

      final result = await stack.container
          .read(profileRepositoryProvider)
          .updateDisplayName('Giovanni');

      expect(result.isOk, isTrue);
      final row = await stack.db.getOptional(
        'SELECT display_name FROM profiles WHERE id = ?',
        ['user-1'],
      );
      expect(row?['display_name'], 'Giovanni');
    });

    test('watchMine reage à escrita sem recarregar', () async {
      final stack = await localStack();
      await seedProfile(stack.db);
      final repo = stack.container.read(profileRepositoryProvider);

      // A expectativa é montada **antes** da escrita: é a inscrição já viva que
      // torna isto uma prova de reatividade. `emitsThrough` e não
      // `emitsInOrder` porque a primeira emissão do `watch` pode chegar dos
      // dois lados da escrita — o que importa é o valor novo aparecer sozinho.
      final reacted = expectLater(
        repo.watchMine().map((p) => p?.displayName),
        emitsThrough('Giovanni'),
      );

      await repo.updateDisplayName('Giovanni');
      await reacted;
    });

    // O caso que o UPDATE silencioso esconde. Sem a checagem de existência no
    // repositório, isto passaria como sucesso e o nome nunca apareceria.
    test('sem a linha de profiles, recusa em vez de fingir sucesso', () async {
      final stack = await localStack();

      final result = await stack.container
          .read(profileRepositoryProvider)
          .updateDisplayName('Giovanni');

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });

    test('trocar duas vezes deixa o último nome, sem duplicar linha', () async {
      final stack = await localStack();
      await seedProfile(stack.db);
      final repo = stack.container.read(profileRepositoryProvider);

      await repo.updateDisplayName('Primeiro');
      await repo.updateDisplayName('Segundo');

      final rows = await stack.db.getAll('SELECT * FROM profiles');
      expect(rows, hasLength(1));
      expect(rows.first['display_name'], 'Segundo');
    });

    test('acento e emoji sobrevivem à ida e volta pelo SQLite', () async {
      final stack = await localStack();
      await seedProfile(stack.db);
      final repo = stack.container.read(profileRepositoryProvider);

      await repo.updateDisplayName('Ana Antônia 🌱');

      final profile = await repo.watchMine().first;
      expect(profile?.displayName, 'Ana Antônia 🌱');
    });
  });

  group('space_members: a coluna nova no INSERT', () {
    test('criar espaço insere a membership com display_name', () async {
      final stack = await localStack();

      final created = await stack.container
          .read(spacesRepositoryProvider)
          .createShared(type: SpaceType.group, name: 'República');

      expect(created.isOk, isTrue);
      final space = created.valueOrNull!;

      // O INSERT tem dez colunas e dez placeholders desde que `display_name`
      // entrou. Uma lista posicional fora de sincronia falharia aqui, na view,
      // e não numa asserção de mock.
      final members = await stack.db.getAll(
        'SELECT * FROM space_members WHERE space_id = ?',
        [space.id],
      );
      expect(members, hasLength(1));
      expect(members.first['user_id'], 'user-1');
      // Nulo na criação local de propósito: quem preenche é o trigger do
      // Postgres, e a própria linha da pessoa lê o nome de `profiles`.
      expect(members.first['display_name'], isNull);
    });

    test('watchMembers devolve o display_name que veio do sync', () async {
      final stack = await localStack();
      await seedSpace(stack.db);
      await stack.db.execute(
        'INSERT INTO space_members (id, space_id, user_id, role, status, '
        'display_name, joined_at, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'member-2',
          'space-1',
          'user-2',
          'editor',
          'active',
          'Ana Prado',
          '2026-07-12T00:00:00.000Z',
          '2026-07-12T00:00:00.000Z',
          '2026-07-12T00:00:00.000Z',
        ],
      );

      final members = await stack.container
          .read(spacesRepositoryProvider)
          .watchMembers('space-1')
          .first;

      expect(members, hasLength(1));
      expect(members.first.displayName, 'Ana Prado');
      expect(members.first, isA<SpaceMember>());
    });
  });
}
