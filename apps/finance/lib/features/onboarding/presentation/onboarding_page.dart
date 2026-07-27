import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transactions/presentation/quick_entry_sheet.dart';
import 'onboarding_pillars.dart';
import 'onboarding_providers.dart';

/// Apresentação inicial: três telas de pilar e a entrega na primeira ação
/// (PRD §10.2).
///
/// ## Duas decisões que dão a forma da tela
///
/// **O produto se apresenta com o próprio produto.** Cada pilar carrega um
/// fragmento real da interface em vez de ilustração — ver `onboarding_pillars`.
///
/// **A apresentação termina *dentro* da ação.** O último toque não larga o
/// usuário numa home vazia com um `+` para procurar: abre o registro rápido com
/// o teclado em pé. A promessa do PRD é o primeiro gasto em 30 segundos, e um
/// botão "Começar" que cai numa tela vazia gasta dez deles em orientação.
///
/// A flag de "já viu" só é gravada quando a folha fecha, e não ao tocar em
/// "Começar": gravar antes tiraria esta tela da árvore no meio da transição —
/// o guard de rota redirecionaria — e a folha morreria com ela.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _controller = PageController();
  final List<OnboardingPillar> _pillars = onboardingPillars();

  var _index = 0;
  var _isHandingOff = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _pillars.length - 1;

  Future<void> _finish() =>
      ref.read(onboardingSeenProvider.notifier).complete();

  Future<void> _advance() async {
    if (_isLast) return _handOff();
    await _controller.nextPage(
      duration: AppMotion.normal,
      curve: AppMotion.easeOut,
    );
  }

  /// Mostra o fundo de entrega e abre o registro rápido em cima dele.
  Future<void> _handOff() async {
    setState(() => _isHandingOff = true);
    // Um frame para o fundo pintar antes da folha subir: sem isto a folha
    // anima sobre a última tela de pilar.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    await QuickEntrySheet.show(context, showFirstRunHint: true);
    if (!mounted) return;
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    if (_isHandingOff) return const _HandoffBackground();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              total: _pillars.length,
              current: _index,
              onSkip: _finish,
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (index) => setState(() => _index = index),
                itemCount: _pillars.length,
                itemBuilder: (context, index) =>
                    _PillarView(pillar: _pillars[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.xxl,
                AppSpacing.screenGutter,
                AppSpacing.xxl,
              ),
              child: AppButton(
                key: const Key('onboarding_advance'),
                label: _isLast ? 'Começar' : 'Avançar',
                onPressed: _advance,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progresso e a saída.
///
/// Progresso em **barras**, não em bolinhas: as barras ecoam a barra de
/// orçamento, que é o motivo visual do produto — bolinha é o sinal genérico de
/// carrossel. "Pular" fica sempre visível, porque dois dos três pilares são
/// promessa, e prender alguém em três telas de promessa para chegar a uma ação
/// de 30 segundos seria a troca errada.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.total,
    required this.current,
    required this.onSkip,
  });

  final int total;
  final int current;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      AppSpacing.md,
      AppSpacing.sm,
      0,
    ),
    child: Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          AnimatedContainer(
            duration: AppMotion.fast,
            height: 3,
            width: i == current ? 30 : 22,
            decoration: BoxDecoration(
              color: i == current
                  ? context.colors.primary
                  : context.tokens.hairlineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
        const Spacer(),
        AppButton(
          key: const Key('onboarding_skip'),
          label: 'Pular',
          variant: AppButtonVariant.ghost,
          expand: false,
          onPressed: onSkip,
        ),
      ],
    ),
  );
}

/// Uma tela de pilar: rótulo, o valor alto, título, texto e o fragmento.
///
/// O fragmento é **ancorado no rodapé** (`Spacer`), não centralizado: assim as
/// três telas compartilham a mesma linha de base e o vão cai sempre no mesmo
/// lugar, mesmo com fragmentos de alturas diferentes. Continua rolável para o
/// caso de fonte grande — aí o `Spacer` encolhe a zero e o conteúdo desliza.
class _PillarView extends StatelessWidget {
  const _PillarView({required this.pillar});

  final OnboardingPillar pillar;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // O bloco de texto rola, o fragmento fica ancorado embaixo. `Spacer` dentro
    // de um `SingleChildScrollView` não serve: ali a altura é ilimitada e um
    // filho com flex estoura.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xxxl),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenGutter,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${pillar.eyebrow} · ',
                        style: context.texts.labelSmall,
                      ),
                      Text(
                        pillar.isAvailable ? 'disponível agora' : 'em breve',
                        style: context.texts.labelSmall?.copyWith(
                          color: pillar.isAvailable
                              ? tokens.brandText
                              : tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenGutter,
                  ),
                  child: _LoudAmount(
                    amount: pillar.amount,
                    isIncome: pillar.isIncomeAmount,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenGutter,
                  ),
                  child: Text(
                    pillar.headline,
                    style: context.texts.headlineSmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.screenGutter,
                    right: AppSpacing.xxxl,
                  ),
                  child: Text(
                    pillar.lede,
                    style: context.texts.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
        if (!pillar.isAvailable) ...[
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.xxl),
            child: _SoonChip(),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        pillar.fragment,
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// O momento alto da tela: um valor, 40px mono tabular.
///
/// Não usa `AmountDisplay` porque aquele é centralizado e existe para valor em
/// digitação; aqui o valor é conteúdo estático e alinhado à esquerda, junto do
/// título.
class _LoudAmount extends StatelessWidget {
  const _LoudAmount({required this.amount, required this.isIncome});

  final Money amount;
  final bool isIncome;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          r'R$',
          style: AppTypography.money.copyWith(color: context.tokens.textMuted),
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        amount.format(withSymbol: false),
        style: AppTypography.balance.copyWith(
          color: isIncome
              ? context.tokens.moneyPositive
              : context.colors.onSurface,
        ),
      ),
    ],
  );
}

/// Marca o pilar que ainda não existe.
///
/// Contorno e texto apagado — **não** âmbar: neste sistema âmbar significa
/// atenção de orçamento e nada mais.
class _SoonChip extends StatelessWidget {
  const _SoonChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      borderRadius: AppRadii.brFull,
      border: Border.all(color: context.tokens.hairline),
    ),
    child: Text(
      'Chega numa fase futura',
      style: context.texts.labelSmall?.copyWith(
        color: context.tokens.textMuted,
      ),
    ),
  );
}

/// Fundo da entrega: a home em repouso, atrás da folha de registro rápido.
///
/// Saldo em `R$ 0,00` na cor de texto desabilitado — nada aconteceu ainda, e a
/// tela diz isso em vez de mostrar um número de mentira.
class _HandoffBackground extends StatelessWidget {
  const _HandoffBackground();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.md),
            Text('Espaço ativo', style: context.texts.labelSmall),
            Text('Pessoal', style: context.texts.titleMedium),
            const SizedBox(height: AppSpacing.xxxl),
            Text('Saldo de julho', style: context.texts.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              r'R$ 0,00',
              style: AppTypography.balance.copyWith(
                color: context.tokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
