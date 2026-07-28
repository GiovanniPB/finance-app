import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import 'spaces_providers.dart';

/// Entrar num espaço com o código do convite (PRD §8.1).
///
/// **É a única tela do app que não funciona offline**, e a mensagem de erro diz
/// isso quando for o caso. A razão está no `SpacesRepository`: quem entra ainda
/// não é membro, então não há nada no SQLite local para escrever — a travessia
/// é uma RPC no Postgres.
///
/// O campo força maiúsculas e recusa o que não pertence ao alfabeto do código
/// enquanto se digita. Não é firula: o alfabeto exclui `0`, `1`, `I`, `L`, `O`
/// e `S` justamente porque o código é lido em voz alta, e deixar digitar um
/// `O` para depois dizer "código inválido" seria punir a pessoa por um símbolo
/// que nunca existiu.
class JoinSpaceSheet extends ConsumerStatefulWidget {
  const JoinSpaceSheet({super.key});

  /// Abre a folha. Devolve o id do espaço em que entrou, ou nulo.
  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const JoinSpaceSheet(),
      );

  @override
  ConsumerState<JoinSpaceSheet> createState() => _JoinSpaceSheetState();
}

class _JoinSpaceSheetState extends ConsumerState<JoinSpaceSheet> {
  final _code = TextEditingController();
  bool _isJoining = false;
  String? _errorMessage;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _isJoining = true;
      _errorMessage = null;
    });

    final result = await ref
        .read(spacesRepositoryProvider)
        .joinByCode(_code.text);

    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        // Trocar para o espaço novo é o ponto de entrar nele. Sem isso a folha
        // fecha e a tela continua exatamente igual.
        ref.read(activeSpaceIdProvider.notifier).select(value);
        Navigator.of(context).pop(value);
      case Err(:final failure):
        setState(() {
          _isJoining = false;
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
                AppSpacing.xs,
              ),
              child: Text('Entrar num espaço', style: context.texts.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                0,
                AppSpacing.screenGutter,
                AppSpacing.lg,
              ),
              child: Text(
                'Peça o código de convite para quem criou o espaço.',
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
                key: const Key('join_code'),
                label: 'Código',
                hint: 'ABCD2345',
                controller: _code,
                enabled: !_isJoining,
                keyboardType: TextInputType.visiblePassword,
                onChanged: (_) => setState(() => _errorMessage = null),
                inputFormatters: [
                  UpperCaseFormatter(),
                  // O alfabeto **exato** do gerador, e não `[A-Z2-9]`: essa
                  // classe mais larga deixava passar `I`, `L`, `O` e `S`, que
                  // são justamente os símbolos que o código exclui. Um teste
                  // pegou a promessa que o filtro não cumpria.
                  FilteringTextInputFormatter.allow(
                    RegExp('[ABCDEFGHJKMNPQRTUVWXYZ23456789]'),
                  ),
                  LengthLimitingTextInputFormatter(8),
                ],
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
                  key: const Key('join_error'),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: AppButton(
                key: const Key('join_submit'),
                label: 'Entrar',
                onPressed: _isJoining ? null : _join,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Converte para maiúsculas enquanto se digita.
///
/// Existe porque o `FilteringTextInputFormatter` que vem depois só aceita o
/// alfabeto maiúsculo do código: sem esta conversão antes, digitar em
/// minúsculas não produziria caractere nenhum, e o campo pareceria travado.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
