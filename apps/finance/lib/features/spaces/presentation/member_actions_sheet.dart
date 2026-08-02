import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../../profile/presentation/profile_providers.dart';
import '../domain/space_member.dart';
import '../domain/space_permissions.dart';
import 'member_copy.dart';

/// O que dá para fazer com um membro: trocar o papel, ou tirar do espaço.
///
/// ─────────────────────────────────────────────────────────────────────────
/// TROCAR O PAPEL APLICA NA HORA; REMOVER PEDE CONFIRMAÇÃO
///
/// As duas ações não têm o mesmo peso. Rebaixar alguém a leitor é reversível
/// num toque, então uma confirmação ali seria só um obstáculo. Remover
/// interrompe o acesso de outra pessoa a um histórico que é dela também — e
/// desfazer exige um convite novo e a outra ponta aceitando. A pergunta extra
/// paga o próprio custo.
///
/// A folha **não** oferece o que a pessoa não pode fazer. Ver
/// [SpacePermissions]: a linha de quem criou o espaço não muda de papel nem
/// sai, e a própria linha não se remove — para isso existe "Sair do espaço", na
/// tela de trás, com outra frase.
class MemberActionsSheet extends ConsumerStatefulWidget {
  const MemberActionsSheet({
    required this.member,
    required this.permissions,
    super.key,
  });

  final SpaceMember member;
  final SpacePermissions permissions;

  static Future<void> show(
    BuildContext context, {
    required SpaceMember member,
    required SpacePermissions permissions,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        MemberActionsSheet(member: member, permissions: permissions),
  );

  @override
  ConsumerState<MemberActionsSheet> createState() => _MemberActionsSheetState();
}

class _MemberActionsSheetState extends ConsumerState<MemberActionsSheet> {
  bool _isSaving = false;
  bool _isConfirmingRemoval = false;
  String? _errorMessage;

  Future<void> _apply(
    Future<Result<void, Failure>> Function() operation,
  ) async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await operation();
    if (!mounted) return;

    switch (result) {
      case Ok():
        Navigator.of(context).pop();
      case Err(:final failure):
        setState(() {
          _isSaving = false;
          _errorMessage = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final permissions = widget.permissions;
    final repository = ref.read(spacesRepositoryProvider);
    final today = ref.watch(clockProvider)();
    final error = _errorMessage;

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
                AppSpacing.lg,
              ),
              child: Text(
                // `.text` e não `.label`: num título não há duas cores para
                // separar o nome do qualificador, então eles voltam a ser uma
                // frase só.
                MemberCopy.identity(
                  member: member,
                  permissions: permissions,
                  today: today,
                  myDisplayName: ref.watch(myDisplayNameProvider),
                ).text,
                style: context.texts.titleLarge,
              ),
            ),

            if (permissions.canChangeRoleOf(member)) ...[
              const _SectionLabel('O que esta pessoa pode fazer'),
              for (final role in SpaceRole.values)
                _RoleOption(
                  role: role,
                  isSelected: member.role == role,
                  onTap: _isSaving || member.role == role
                      ? null
                      : () => _apply(
                          () => repository.changeRole(
                            memberId: member.id,
                            role: role,
                          ),
                        ),
                ),
            ],

            if (permissions.canRemove(member)) ...[
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter,
                ),
                child: _isConfirmingRemoval
                    ? _RemovalConfirmation(
                        isSaving: _isSaving,
                        onConfirm: () =>
                            _apply(() => repository.removeMember(member.id)),
                        onCancel: () =>
                            setState(() => _isConfirmingRemoval = false),
                      )
                    : AppButton(
                        key: const Key('member_remove'),
                        label: 'Remover do espaço',
                        variant: AppButtonVariant.danger,
                        onPressed: _isSaving
                            ? null
                            : () => setState(() => _isConfirmingRemoval = true),
                      ),
              ),
            ],

            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.md,
                  AppSpacing.screenGutter,
                  0,
                ),
                child: Text(
                  error,
                  key: const Key('member_action_error'),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// A confirmação abre **no lugar** do botão, e não num diálogo.
///
/// Um diálogo tira o contexto da tela justamente quando ele importa: a frase de
/// consequência precisa ser lida ao lado de quem vai ser removido.
class _RemovalConfirmation extends StatelessWidget {
  const _RemovalConfirmation({
    required this.isSaving,
    required this.onConfirm,
    required this.onCancel,
  });

  final bool isSaving;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        // O que fica é tão importante quanto o que sai: sem esta frase, é
        // razoável temer que remover alguém apague os lançamentos dela.
        'Esta pessoa perde o acesso ao espaço. O que ela lançou continua '
        'aqui, e ela pode voltar com um convite novo.',
        style: context.texts.bodySmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: AppButton(
              key: const Key('member_remove_cancel'),
              label: 'Cancelar',
              variant: AppButtonVariant.secondary,
              onPressed: isSaving ? null : onCancel,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AppButton(
              key: const Key('member_remove_confirm'),
              label: 'Remover',
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      0,
      AppSpacing.screenGutter,
      AppSpacing.sm,
    ),
    child: Text(
      text,
      style: context.texts.labelMedium?.copyWith(
        color: context.tokens.textMuted,
      ),
    ),
  );
}

/// Um papel, com o que ele permite escrito ao lado.
///
/// Mesma decisão do `_TypeOption` do formulário de espaço: "Editor" e "Leitor"
/// não dizem o que cada um pode, e é justamente isso que se está escolhendo.
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  final SpaceRole role;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        0,
        AppSpacing.screenGutter,
        AppSpacing.sm,
      ),
      child: Material(
        color: isSelected ? tokens.brandSubtle : Colors.transparent,
        borderRadius: AppRadii.brLg,
        child: InkWell(
          key: Key('member_role_${role.db}'),
          onTap: onTap,
          borderRadius: AppRadii.brLg,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: AppRadii.brLg,
              border: Border.all(
                color: isSelected ? tokens.brandBorder : tokens.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected ? tokens.brandText : tokens.textMuted,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.label,
                        style: context.texts.titleSmall?.copyWith(
                          color: isSelected ? tokens.brandText : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        role.description,
                        style: context.texts.bodySmall?.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
