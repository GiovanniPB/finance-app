import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../domain/space.dart';
import 'spaces_providers.dart';

/// Criar um espaço compartilhado (PRD §4, §12.1).
///
/// ─────────────────────────────────────────────────────────────────────────
/// O TIPO É ESCOLHIDO NA CRIAÇÃO E NÃO SE TROCA DEPOIS
///
/// `household` e `group` têm regras **opostas** em privacidade, foco e
/// encerramento (PRD §4.2) — não são um "compartilhado genérico" com um
/// interruptor. Trocar o tipo de um espaço com histórico mudaria, em bloco, o
/// que cada membro pode ver de trás para frente. Por isso a escolha aparece
/// aqui, uma vez, com a consequência escrita ao lado de cada opção.
///
/// A `privacy_policy` **não** é perguntada: ela é derivada do tipo no
/// repository. Oferecer as duas convidaria a criar um household sem
/// transparência, que é um tipo que não existe.
class SpaceFormSheet extends ConsumerStatefulWidget {
  const SpaceFormSheet({super.key});

  /// Abre a folha. Devolve o id do espaço criado, ou nulo se desistiu.
  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const SpaceFormSheet(),
      );

  @override
  ConsumerState<SpaceFormSheet> createState() => _SpaceFormSheetState();
}

class _SpaceFormSheetState extends ConsumerState<SpaceFormSheet> {
  final _name = TextEditingController();
  SpaceType _type = SpaceType.group;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await ref
        .read(spacesRepositoryProvider)
        .createShared(type: _type, name: _name.text);

    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        // Entrar no espaço recém-criado é o passo que a pessoa faria em
        // seguida de qualquer jeito — e sem isso a folha fecha e nada visível
        // muda, porque a home continua no espaço anterior.
        ref.read(activeSpaceIdProvider.notifier).select(value.id);
        Navigator.of(context).pop(value.id);
      case Err(:final failure):
        setState(() {
          _isSaving = false;
          _errorMessage = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _errorMessage;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
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
              child: Text('Novo espaço', style: context.texts.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
              child: AppTextField(
                key: const Key('space_name'),
                label: 'Nome',
                hint: 'Viagem ao Chile, Casa, República…',
                controller: _name,
                enabled: !_isSaving,
                onChanged: (_) => setState(() => _errorMessage = null),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final type in [SpaceType.group, SpaceType.household])
              _TypeOption(
                type: type,
                isSelected: _type == type,
                onTap: _isSaving ? null : () => setState(() => _type = type),
              ),
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
                  key: const Key('space_form_error'),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.tokens.moneyOver,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: AppButton(
                key: const Key('space_form_save'),
                label: 'Criar espaço',
                onPressed: _isSaving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma opção de tipo, com a consequência escrita.
///
/// Cartão em vez de segmento de duas posições: o segmento cabe onde os rótulos
/// bastam ("Gasto"/"Receita"), e aqui **não bastam** — "Grupo" e "Casal" não
/// dizem que um divide despesa e o outro abre tudo. A frase é o conteúdo.
class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  final SpaceType type;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (title, description, icon) = switch (type) {
      SpaceType.group => (
        'Grupo',
        'Dividir despesas e acertar quem deve a quem. Cada um só vê o que '
            'foi lançado aqui.',
        Icons.groups_outlined,
      ),
      SpaceType.household => (
        'Casal',
        'Vida financeira junta: orçamento e metas em comum, e tudo visível '
            'para os dois.',
        Icons.favorite_outline,
      ),
      SpaceType.personal => ('Pessoal', '', Icons.person_outline),
    };

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
          key: Key('space_type_${type.db}'),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: isSelected ? tokens.brandText : tokens.textMuted,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.texts.titleSmall?.copyWith(
                          color: isSelected ? tokens.brandText : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        description,
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
