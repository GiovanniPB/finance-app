import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../domain/space.dart';
import '../domain/space_member.dart';
import 'spaces_providers.dart';

/// Quem está no espaço, e o código para chamar mais gente.
///
/// **O código é pedido ao abrir, não antes.** Ele vem de uma RPC, e gerar um
/// convite para todo espaço listado seria uma ida à rede por linha da tela de
/// Espaços — a maioria delas jogada fora sem ninguém convidar ninguém.
///
/// Quem não é admin não vê o bloco de convite (matriz do PRD §7). Não é um
/// botão desabilitado: um controle que existe e não responde é pior do que a
/// ausência dele, porque promete uma permissão que não há.
class SpaceDetailSheet extends ConsumerStatefulWidget {
  const SpaceDetailSheet({required this.space, super.key});

  final Space space;

  static Future<void> show(BuildContext context, {required Space space}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SpaceDetailSheet(space: space),
      );

  @override
  ConsumerState<SpaceDetailSheet> createState() => _SpaceDetailSheetState();
}

class _SpaceDetailSheetState extends ConsumerState<SpaceDetailSheet> {
  String? _code;
  String? _codeError;
  bool _isLoadingCode = false;

  Future<void> _loadCode() async {
    setState(() {
      _isLoadingCode = true;
      _codeError = null;
    });

    final result = await ref
        .read(spacesRepositoryProvider)
        .inviteCode(widget.space.id);

    if (!mounted) return;
    setState(() {
      _isLoadingCode = false;
      switch (result) {
        case Ok(:final value):
          _code = value;
        case Err(:final failure):
          _codeError = failure.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final space = widget.space;
    final members =
        ref.watch(spaceMembersProvider(space.id)).asData?.value ??
        const <SpaceMember>[];
    final myRole = ref.watch(myRoleInSpaceProvider(space.id));

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrabHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                0,
                AppSpacing.screenGutter,
                AppSpacing.xs,
              ),
              child: Text(space.name, style: context.texts.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                0,
                AppSpacing.screenGutter,
                AppSpacing.lg,
              ),
              child: Text(
                _spaceSubtitle(space, members.length),
                style: context.texts.bodySmall?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ),
            for (final member in members)
              _MemberRow(
                member: member,
                isOwner: member.userId == space.ownerId,
              ),
            if (myRole?.canManageMembers ?? false) ...[
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter,
                ),
                child: _InviteBlock(
                  code: _code,
                  error: _codeError,
                  isLoading: _isLoadingCode,
                  onGenerate: _loadCode,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  static String _spaceSubtitle(Space space, int memberCount) {
    final people = memberCount == 1 ? '1 pessoa' : '$memberCount pessoas';
    return switch (space.type) {
      SpaceType.group =>
        'Grupo · $people · cada um vê só o que foi lançado '
            'aqui',
      SpaceType.household => 'Casal · $people · tudo visível para todos',
      SpaceType.personal => 'Pessoal · só você',
    };
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.isOwner});

  final SpaceMember member;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const CategorySwatch.brand(icon: Icons.person_outline),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Sem nome ainda: `profiles.display_name` não é sincronizado
                  // para outros membros, e `username` não existe (débito do
                  // roadmap). Mostrar um id cru seria pior do que o papel.
                  isOwner ? 'Quem criou' : member.role.label,
                  style: context.texts.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  member.role.description,
                  style: context.texts.labelSmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// O código, ou o caminho até ele.
class _InviteBlock extends StatelessWidget {
  const _InviteBlock({
    required this.code,
    required this.error,
    required this.isLoading,
    required this.onGenerate,
  });

  final String? code;
  final String? error;
  final bool isLoading;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final current = code;
    final failure = error;

    if (current == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppButton(
            key: const Key('space_invite_generate'),
            label: isLoading ? 'Gerando…' : 'Convidar alguém',
            variant: AppButtonVariant.secondary,
            onPressed: isLoading ? null : onGenerate,
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                failure,
                key: const Key('space_invite_error'),
                style: context.texts.bodySmall?.copyWith(
                  color: tokens.moneyOver,
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      key: const Key('space_invite_code'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: AppRadii.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Código do convite',
            style: context.texts.labelMedium?.copyWith(
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  current,
                  // Mono com espaçamento largo: o código é ditado em voz alta e
                  // copiado à mão, e é aí que caractere grudado vira erro.
                  style: AppTypography.moneyLarge.copyWith(letterSpacing: 4),
                ),
              ),
              IconButton(
                key: const Key('space_invite_copy'),
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copiar',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: current));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Vale por 7 dias. Quem entrar com ele pode lançar e editar.',
            style: context.texts.labelSmall?.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}
