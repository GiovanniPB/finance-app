import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../data/profile_repository_impl.dart';
import '../domain/profile.dart';

/// Definir o próprio nome.
///
/// É o **único** lugar do app onde `profiles.display_name` é escrito. O
/// cadastro não pergunta o nome de propósito (ver o contrato da fatia
/// `nome-de-membro`): pedir mais um campo na porta de entrada custa mais do que
/// deixar a pessoa entrar e se apresentar depois.
///
/// A frase de apoio existe porque um campo "Nome" solto no Perfil parece
/// vaidade. Dizendo para que serve — os outros membros veem —, ele vira uma
/// coisa que se preenche.
class ProfileNameSheet extends ConsumerStatefulWidget {
  const ProfileNameSheet({required this.profile, super.key});

  final Profile profile;

  static Future<void> show(BuildContext context, {required Profile profile}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ProfileNameSheet(profile: profile),
      );

  @override
  ConsumerState<ProfileNameSheet> createState() => _ProfileNameSheetState();
}

class _ProfileNameSheetState extends ConsumerState<ProfileNameSheet> {
  late final _name = TextEditingController(
    text: widget.profile.displayName ?? '',
  );
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
        .read(profileRepositoryProvider)
        .updateDisplayName(_name.text);

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
                AppSpacing.sm,
              ),
              child: Text('Seu nome', style: context.texts.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                0,
                AppSpacing.screenGutter,
                AppSpacing.lg,
              ),
              child: Text(
                'Quem divide um espaço com você vê este nome na lista de '
                'membros.',
                style: context.texts.bodySmall?.copyWith(
                  color: context.tokens.textMuted,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
              child: AppTextField(
                key: const Key('profile_name_field'),
                label: 'Nome',
                controller: _name,
                enabled: !_isSaving,
                // O limite é o mesmo do `check` no Postgres. Cortar na
                // digitação evita a recusa que só apareceria depois de tocar
                // em Salvar — o repositório ainda valida, para a regra não
                // depender da tela.
                inputFormatters: [
                  LengthLimitingTextInputFormatter(
                    ProfileRepositoryImpl.maxNameLength,
                  ),
                ],
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
                  key: const Key('profile_name_error'),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: AppButton(
                key: const Key('profile_name_save'),
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
