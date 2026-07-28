import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../domain/space.dart';

/// Renomear o espaço.
///
/// Só o nome. O **tipo** não aparece aqui de propósito: ele decide o que cada
/// membro enxerga do histórico (PRD §4.2), e trocá-lo num espaço que já tem
/// lançamento mudaria isso de trás para frente. Desde a migration
/// `20260728210321` o banco recusa a troca — esta folha é o lado da UI da
/// mesma decisão.
class SpaceRenameSheet extends ConsumerStatefulWidget {
  const SpaceRenameSheet({required this.space, super.key});

  final Space space;

  static Future<void> show(BuildContext context, {required Space space}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SpaceRenameSheet(space: space),
      );

  @override
  ConsumerState<SpaceRenameSheet> createState() => _SpaceRenameSheetState();
}

class _SpaceRenameSheetState extends ConsumerState<SpaceRenameSheet> {
  late final _name = TextEditingController(text: widget.space.name);
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
        .rename(spaceId: widget.space.id, name: _name.text);

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
    final error = _errorMessage;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
              child: Text('Renomear espaço', style: context.texts.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
              child: AppTextField(
                key: const Key('space_rename_name'),
                label: 'Nome',
                controller: _name,
                enabled: !_isSaving,
                onChanged: (_) => setState(() => _errorMessage = null),
              ),
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
                  key: const Key('space_rename_error'),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: AppButton(
                key: const Key('space_rename_save'),
                label: 'Salvar',
                isLoading: _isSaving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
