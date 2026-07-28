import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// O código do convite, ou o caminho até ele.
///
/// **O código é pedido ao abrir a tela, não antes.** Ele vem de uma RPC, e
/// gerar um convite para todo espaço listado seria uma ida à rede por linha da
/// tela de Espaços — a maioria delas jogada fora sem ninguém convidar ninguém.
///
/// Quem não é admin não vê este bloco. Não é um botão desabilitado: um controle
/// que existe e não responde é pior do que a ausência dele, porque promete uma
/// permissão que não há.
class InviteBlock extends StatelessWidget {
  const InviteBlock({
    required this.code,
    required this.error,
    required this.isLoading,
    required this.onGenerate,
    super.key,
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
                  color: context.colors.error,
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
            style: context.texts.labelMedium?.copyWith(color: tokens.textMuted),
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
