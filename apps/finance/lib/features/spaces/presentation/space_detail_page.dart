import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../domain/space.dart';
import '../domain/space_member.dart';
import '../domain/space_permissions.dart';
import 'invite_block.dart';
import 'member_actions_sheet.dart';
import 'member_copy.dart';
import 'space_rename_sheet.dart';
import 'space_summary_card.dart';
import 'spaces_providers.dart';

/// A tela de um espaço: o que ele é, quem está nele, e o que dá para mudar.
///
/// ─────────────────────────────────────────────────────────────────────────
/// POR QUE UMA PÁGINA, E NÃO A FOLHA QUE HAVIA ANTES
///
/// A folha cabia enquanto o conteúdo era "quem está aqui + um código". Com
/// resumo, papéis, renomear, arquivar e sair, ela viraria uma folha rolável do
/// tamanho da tela — que é uma página com menos afordância de volta e sem lugar
/// para título fixo.
///
/// **Abrir não é usar.** O toque na lista traz para cá; trocar o espaço ativo é
/// um controle próprio, aqui e na lista. Eram a mesma coisa antes, e a fusão
/// escondia a gestão atrás de um efeito colateral.
///
/// Quando o espaço some do banco local — o que acontece um instante depois de
/// sair ou de ser removido, porque as sync rules deixam de entregar o bucket —
/// a página troca o conteúdo por uma explicação, em vez de se fechar sozinha.
/// Fechar sozinha devolveria a pessoa à lista sem dizer o que houve, e "sumiu"
/// sem frase é exatamente o que esta base já pagou caro para não repetir.
class SpaceDetailPage extends ConsumerStatefulWidget {
  const SpaceDetailPage({required this.spaceId, super.key});

  final String spaceId;

  @override
  ConsumerState<SpaceDetailPage> createState() => _SpaceDetailPageState();
}

class _SpaceDetailPageState extends ConsumerState<SpaceDetailPage> {
  String? _code;
  String? _codeError;
  bool _isLoadingCode = false;

  /// `true` depois que a página já viu o espaço existir.
  ///
  /// Sem esta memória não há como distinguir "ainda não sincronizou" de "saiu
  /// do espaço": os dois são `null`. Fechar no primeiro seria fechar a tela
  /// durante o boot; não fechar no segundo deixaria a pessoa olhando um espaço
  /// do qual acabou de sair.
  bool _hasSeenSpace = false;

  Future<void> _loadCode() async {
    setState(() {
      _isLoadingCode = true;
      _codeError = null;
    });

    final result = await ref
        .read(spacesRepositoryProvider)
        .inviteCode(widget.spaceId);

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
    final permissions = ref.watch(spacePermissionsProvider(widget.spaceId));

    if (permissions == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _hasSeenSpace
              ? const _SpaceGone()
              : const CircularProgressIndicator(),
        ),
      );
    }
    _hasSeenSpace = true;

    final space = permissions.space;
    final members =
        ref.watch(spaceMembersProvider(space.id)).asData?.value ??
        const <SpaceMember>[];
    final isActive = ref.watch(activeSpaceProvider)?.id == space.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(space.name),
        actions: [
          if (permissions.canRename)
            IconButton(
              key: const Key('space_rename'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Renomear',
              onPressed: () => SpaceRenameSheet.show(context, space: space),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: [
          if (space.isArchived)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.md,
                AppSpacing.screenGutter,
                0,
              ),
              child: _ArchivedBanner(),
            ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: SpaceSummaryCard(
              space: space,
              memberCount: members.length,
              summary: ref.watch(spaceMonthSummaryProvider(space.id)),
            ),
          ),

          if (!isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                0,
                AppSpacing.screenGutter,
                AppSpacing.xl,
              ),
              child: AppButton(
                key: const Key('space_use'),
                label: 'Usar este espaço',
                onPressed: () {
                  ref.read(activeSpaceIdProvider.notifier).select(space.id);
                  Navigator.of(context).pop();
                },
              ),
            ),

          if (permissions.isShared) ...[
            const _SectionTitle('Quem está aqui'),
            for (final member in members)
              _MemberRow(
                member: member,
                permissions: permissions,
                today: ref.watch(clockProvider)(),
              ),
            const SizedBox(height: AppSpacing.xl),
          ],

          if (permissions.canInvite)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
              child: InviteBlock(
                code: _code,
                error: _codeError,
                isLoading: _isLoadingCode,
                onGenerate: _loadCode,
              ),
            ),

          if (permissions.canArchive || permissions.canLeave)
            _DangerZone(permissions: permissions),
        ],
      ),
    );
  }
}

/// Sair e arquivar, embaixo e juntos.
///
/// Embaixo porque são raras e irreversíveis-na-prática; juntas porque são a
/// mesma pergunta ("como eu encerro isso?") com a resposta dependendo de quem
/// está perguntando. Quem criou o espaço não sai — a frase explica em vez de só
/// esconder o botão, senão a conclusão razoável é que a saída não existe.
class _DangerZone extends ConsumerStatefulWidget {
  const _DangerZone({required this.permissions});

  final SpacePermissions permissions;

  @override
  ConsumerState<_DangerZone> createState() => _DangerZoneState();
}

class _DangerZoneState extends ConsumerState<_DangerZone> {
  bool _isConfirmingLeave = false;
  bool _isConfirmingArchive = false;
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _run(Future<Result<void, Failure>> Function() operation) async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await operation();
    if (!mounted) return;

    switch (result) {
      case Ok():
        // Sair faz o espaço sumir do banco local, e a página se fecha sozinha
        // por causa disso. Arquivar não: o espaço continua sincronizando, e a
        // tela precisa ficar de pé para mostrar o aviso de arquivado.
        setState(() {
          _isSaving = false;
          _isConfirmingLeave = false;
          _isConfirmingArchive = false;
        });
      case Err(:final failure):
        setState(() {
          _isSaving = false;
          _errorMessage = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = widget.permissions;
    final repository = ref.read(spacesRepositoryProvider);
    final error = _errorMessage;
    final cannotLeave = permissions.whyCannotLeave;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: context.tokens.hairline),
          const SizedBox(height: AppSpacing.lg),

          if (permissions.canArchive)
            _Destructive(
              buttonKey: const Key('space_archive'),
              confirmKey: const Key('space_archive_confirm'),
              cancelKey: const Key('space_archive_cancel'),
              label: 'Arquivar espaço',
              confirmLabel: 'Arquivar',
              explanation:
                  'Ninguém mais lança neste espaço, e o histórico continua '
                  'visível para quem participou. Não apaga nada.',
              isConfirming: _isConfirmingArchive,
              isSaving: _isSaving,
              onStart: () => setState(() => _isConfirmingArchive = true),
              onCancel: () => setState(() => _isConfirmingArchive = false),
              onConfirm: () => _run(
                () => repository.archive(permissions.space.id),
              ),
            ),

          if (permissions.canLeave) ...[
            if (permissions.canArchive) const SizedBox(height: AppSpacing.md),
            _Destructive(
              buttonKey: const Key('space_leave'),
              confirmKey: const Key('space_leave_confirm'),
              cancelKey: const Key('space_leave_cancel'),
              label: 'Sair do espaço',
              confirmLabel: 'Sair',
              explanation:
                  'Você perde o acesso a este espaço e a tudo que está nele. '
                  'O que você lançou continua aqui para quem fica, e dá para '
                  'voltar com um convite novo.',
              isConfirming: _isConfirmingLeave,
              isSaving: _isSaving,
              onStart: () => setState(() => _isConfirmingLeave = true),
              onCancel: () => setState(() => _isConfirmingLeave = false),
              onConfirm: () => _run(
                () => repository.leave(permissions.space.id),
              ),
            ),
          ] else if (cannotLeave != null)
            Text(
              cannotLeave,
              key: const Key('space_cannot_leave'),
              style: context.texts.bodySmall?.copyWith(
                color: context.tokens.textMuted,
              ),
            ),

          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                error,
                key: const Key('space_danger_error'),
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Botão destrutivo que vira explicação + confirmação no mesmo lugar.
class _Destructive extends StatelessWidget {
  const _Destructive({
    required this.buttonKey,
    required this.confirmKey,
    required this.cancelKey,
    required this.label,
    required this.confirmLabel,
    required this.explanation,
    required this.isConfirming,
    required this.isSaving,
    required this.onStart,
    required this.onCancel,
    required this.onConfirm,
  });

  final Key buttonKey;
  final Key confirmKey;
  final Key cancelKey;
  final String label;
  final String confirmLabel;
  final String explanation;
  final bool isConfirming;
  final bool isSaving;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    if (!isConfirming) {
      return AppButton(
        key: buttonKey,
        label: label,
        variant: AppButtonVariant.secondary,
        onPressed: isSaving ? null : onStart,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          explanation,
          style: context.texts.bodySmall?.copyWith(
            color: context.tokens.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AppButton(
                key: cancelKey,
                label: 'Cancelar',
                variant: AppButtonVariant.secondary,
                onPressed: isSaving ? null : onCancel,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                key: confirmKey,
                label: confirmLabel,
                variant: AppButtonVariant.danger,
                isLoading: isSaving,
                onPressed: onConfirm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.permissions,
    required this.today,
  });

  final SpaceMember member;
  final SpacePermissions permissions;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Sem nenhuma das duas, a linha não é tocável — e não deve parecer.
    final isManageable =
        permissions.canChangeRoleOf(member) || permissions.canRemove(member);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.xxs,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.brLg,
        child: InkWell(
          key: Key('member_${member.id}'),
          borderRadius: AppRadii.brLg,
          onTap: isManageable
              ? () => MemberActionsSheet.show(
                  context,
                  member: member,
                  permissions: permissions,
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                const CategorySwatch.brand(icon: Icons.person_outline),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        MemberCopy.identity(
                          member: member,
                          permissions: permissions,
                          today: today,
                        ),
                        style: context.texts.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        MemberCopy.role(member.role),
                        style: context.texts.labelSmall?.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isManageable)
                  Icon(Icons.chevron_right, size: 20, color: tokens.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchivedBanner extends StatelessWidget {
  const _ArchivedBanner();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('space_archived_banner'),
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      // Poço, não alerta: arquivado é um estado escolhido, não um problema.
      // Vermelho aqui leria como erro numa tela onde nada deu errado.
      color: context.tokens.surfaceSunken,
      borderRadius: AppRadii.brLg,
    ),
    child: Text(
      'Espaço arquivado. O histórico continua aqui; novos lançamentos, não.',
      style: context.texts.bodySmall?.copyWith(color: context.tokens.textMuted),
    ),
  );
}

class _SpaceGone extends StatelessWidget {
  const _SpaceGone();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.screenGutter),
    child: AppEmptyState(
      icon: Icons.exit_to_app,
      title: 'Você não está mais neste espaço',
      message: 'Ele saiu deste aparelho junto com o que era dele.',
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      0,
      AppSpacing.screenGutter,
      AppSpacing.sm,
    ),
    child: Text(title, style: context.texts.titleSmall),
  );
}
