import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/space.dart';
import 'join_space_sheet.dart';
import 'space_detail_page.dart';
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
/// ─────────────────────────────────────────────────────────────────────────
/// O TOQUE ABRE O ESPAÇO; O CÍRCULO À DIREITA TROCA PARA ELE
///
/// Era o contrário: tocar trocava de contexto, e um ícone de pessoas abria uma
/// folha com a lista de membros. Inverteu porque o que há para fazer com um
/// espaço deixou de caber numa folha — papéis, convite, renomear, arquivar,
/// sair — e porque "abrir" e "passar a usar" são perguntas diferentes que
/// estavam grudadas numa só.
///
/// Trocar continua a **um** toque: o círculo à direita é o controle, e ele lê
/// como seleção porque é isso que ele é. O que mudou é que trocar de espaço
/// virou uma escolha explícita em vez de efeito colateral de abrir.
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
            // `Navigator.push` e não uma rota do go_router: é o idioma que o
            // app já usa para tela de detalhe (orçamentos, lançamentos), e o
            // router aqui existe para os portões de auth, não para navegação
            // interna. Vira rota nomeada quando deep link for requisito.
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SpaceDetailPage(spaceId: space.id),
              ),
            ),
            onUse: () =>
                ref.read(activeSpaceIdProvider.notifier).select(space.id),
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
    required this.onOpen,
    required this.onUse,
  });

  final Space space;
  final bool isActive;

  /// Abre a tela do espaço. Vale para o Pessoal também: ele tem resumo e nome,
  /// mesmo sem membros para gerenciar — e uma linha que não responde ao toque,
  /// no meio de outras que respondem, lê como bug.
  final VoidCallback onOpen;

  final VoidCallback onUse;

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
          key: Key('space_open_${space.id}'),
          onTap: onOpen,
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
                // Marca **e** controle na mesma posição: o círculo cheio diz
                // "é este" e o vazio convida a trocar. Dois widgets diferentes
                // aqui fariam a coluna dançar entre as linhas.
                IconButton(
                  key: Key('space_use_${space.id}'),
                  icon: Icon(
                    isActive
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isActive ? tokens.brandText : tokens.textMuted,
                  ),
                  tooltip: isActive ? 'Em uso' : 'Usar este espaço',
                  onPressed: isActive ? null : onUse,
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
