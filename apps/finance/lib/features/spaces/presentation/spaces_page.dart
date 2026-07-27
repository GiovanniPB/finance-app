import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/space.dart';
import 'spaces_providers.dart';

/// Lista de espaços do usuário, com troca de contexto.
///
/// Na Fase 0 só existe o Espaço Pessoal (criado no signup). Criar espaço
/// `household`/`group` é Fase 2 — a tela existe agora para a aba não ser um
/// buraco e para a troca de contexto já funcionar quando houver mais de um.
class SpacesPage extends ConsumerWidget {
  const SpacesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider).asData?.value ?? const <Space>[];
    final active = ref.watch(activeSpaceProvider);

    if (spaces.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            AppSpacing.lg,
          ),
          child: Text('Espaços', style: context.texts.displaySmall),
        ),
        for (final space in spaces)
          _SpaceTile(
            space: space,
            isActive: space.id == active?.id,
            onTap: () =>
                ref.read(activeSpaceIdProvider.notifier).select(space.id),
          ),
        const Padding(
          padding: EdgeInsets.all(AppSpacing.screenGutter),
          child: AppEmptyState(
            icon: Icons.group_add_outlined,
            title: 'Dividir ou somar com alguém',
            message:
                'Espaços de casal e de grupo entram na fase de colaboração, '
                'depois que o registro individual estiver redondo.',
          ),
        ),
      ],
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.space,
    required this.isActive,
    required this.onTap,
  });

  final Space space;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        0,
        AppSpacing.screenGutter,
        AppSpacing.md,
      ),
      child: Material(
        color: isActive
            ? tokens.brandSubtle
            : context.colors.surfaceContainerLow,
        borderRadius: AppRadii.brXl,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.brXl,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: AppRadii.brXl,
              border: Border.all(
                color: isActive ? context.colors.primary : tokens.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _iconFor(space.type),
                  color: isActive ? tokens.brandText : tokens.textMuted,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(space.name, style: context.texts.titleSmall),
                      Text(
                        _labelFor(space.type),
                        style: context.texts.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Icon(Icons.check_circle, size: 20, color: tokens.brandText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(SpaceType type) => switch (type) {
    SpaceType.personal => Icons.person_outline,
    SpaceType.household => Icons.favorite_outline,
    SpaceType.group => Icons.groups_outlined,
  };

  static String _labelFor(SpaceType type) => switch (type) {
    SpaceType.personal => 'Só seu',
    SpaceType.household => 'Vida conjunta',
    SpaceType.group => 'Grupo',
  };
}
