import 'package:finance/di/providers.dart';
import 'package:finance/features/spaces/domain/space.dart';
import 'package:finance/features/spaces/presentation/spaces_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/app_harness.dart' show FakeSpacesRepository;

Space _space(String id, SpaceType type) => Space(
  id: id,
  type: type,
  name: 'Espaço $id',
  ownerId: 'user-1',
  privacy: SpacePrivacy.sharedOnly,
  status: SpaceStatus.active,
  settlementCurrency: 'BRL',
  createdAt: DateTime.utc(2026, 7, 17, 12),
  updatedAt: DateTime.utc(2026, 7, 17, 12),
);

/// Cria o container, mantém [activeSpaceProvider] escutado (o que mantém vivos
/// os providers dos quais ele depende) e aguarda o primeiro emit dos espaços.
Future<ProviderContainer> _ready(List<Space> spaces) async {
  final container = ProviderContainer(
    overrides: [
      spacesRepositoryProvider.overrideWithValue(FakeSpacesRepository(spaces)),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(activeSpaceProvider, (_, _) {});
  addTearDown(sub.close);
  await container.read(spacesProvider.future);
  return container;
}

void main() {
  final personal = _space('p1', SpaceType.personal);
  final groupSpace = _space('g1', SpaceType.group);

  group('activeSpace', () {
    test('é null enquanto não há espaços sincronizados', () async {
      final container = await _ready([]);
      expect(container.read(activeSpaceProvider), isNull);
    });

    test('usa o Espaço Pessoal como padrão', () async {
      final container = await _ready([groupSpace, personal]);
      expect(container.read(activeSpaceProvider)?.id, 'p1');
    });

    test('respeita a seleção explícita do usuário', () async {
      final container = await _ready([personal, groupSpace]);

      container.read(activeSpaceIdProvider.notifier).select('g1');

      expect(container.read(activeSpaceProvider)?.id, 'g1');
    });

    test('seleção inválida cai de volta no padrão pessoal', () async {
      final container = await _ready([personal, groupSpace]);

      container.read(activeSpaceIdProvider.notifier).select('inexistente');

      expect(container.read(activeSpaceProvider)?.id, 'p1');
    });
  });
}
