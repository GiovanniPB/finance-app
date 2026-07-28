import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/space.dart';
import 'join_space_sheet.dart';
import 'space_detail_sheet.dart';
import 'space_form_sheet.dart';
import 'spaces_providers.dart';

/// Lista de espaços do usuário, com troca de contexto (PRD §11.1).
///
/// **Duas ações, e a segunda não é óbvia.** "Criar" é o gesto esperado; "entrar
/// com código" é o que a outra ponta do convite precisa, e sem um caminho
/// próprio ela não existiria — o convidado abriria o app e não teria onde
/// colar o código que recebeu. Por isso as duas ficam lado a lado, e não uma
/// escondida dentro da outra.
///
/// O toque num espaço **troca de contexto**; ver quem está nele é um segundo
/// gesto, no ícone de pessoas. Trocar é o que se faz o tempo todo, e gerenciar
/// é raro: pôr a gestão no toque principal cobraria um gesto extra da ação
/// frequente para favorecer a rara.
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
            onManage: space.isPersonal
                ? null
                : () => SpaceDetailSheet.show(context, space: space),
          ),
        if (ref.watch(sharedSpacesProvider).isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              0,
            ),
            child: AppEmptyState(
              icon: Icons.group_add_outlined,
              title: 'Dividir ou somar com alguém',
              message:
                  'Crie um grupo para dividir despesas, ou um espaço de casal '
                  'para juntar a vida financeira. Quem recebeu um convite '
                  'entra pelo código.',
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const Key('space_new'),
                  label: 'Novo espaço',
                  onPressed: () => SpaceFormSheet.show(context),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  key: const Key('space_join'),
                  label: 'Tenho um código',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => JoinSpaceSheet.show(context),
                ),
              ),
            ],
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
    required this.onManage,
  });

  final Space space;
  final bool isActive;
  final VoidCallback onTap;

  /// Nulo no Espaço Pessoal: ele tem um membro só e não recebe convite
  /// (PRD §4.3), então um botão de gerenciar ali abriria uma tela sem nada.
  final VoidCallback? onManage;

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
                if (onManage != null)
                  IconButton(
                    key: Key('space_manage_${space.id}'),
                    icon: const Icon(Icons.people_outline),
                    tooltip: 'Quem está aqui',
                    onPressed: onManage,
                  ),
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
