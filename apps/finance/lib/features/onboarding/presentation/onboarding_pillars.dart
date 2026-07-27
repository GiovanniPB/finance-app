import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Conteúdo de uma tela de pilar.
///
/// O fragmento é um widget, não uma imagem: a apresentação mostra **a própria
/// interface**. No pilar 1 ele é literalmente a `TransactionTile` da lista; nos
/// pilares 2 e 3 é um esboço, porque as telas de verdade são das fases 1 e 2 e
/// desenhá-las agora seria adivinhar (ver o readme do projeto de design).
@immutable
class OnboardingPillar {
  const OnboardingPillar({
    required this.eyebrow,
    required this.isAvailable,
    required this.amount,
    required this.headline,
    required this.lede,
    required this.fragment,
    this.isIncomeAmount = false,
  });

  /// Ex.: "Pilar 1". O sufixo de disponibilidade é montado pela tela.
  final String eyebrow;

  /// `false` marca o pilar como ainda não construído — e a tela **diz isso**,
  /// em vez de prometer o que não existe.
  final bool isAvailable;

  /// O momento alto: um valor, em 40px mono. Um por tela.
  final Money amount;

  /// Quando `true`, o valor sai na cor de receita (marca) em vez de neutro.
  final bool isIncomeAmount;

  final String headline;
  final String lede;
  final Widget fragment;
}

/// Os três pilares do produto, na ordem em que o PRD os apresenta.
List<OnboardingPillar> onboardingPillars() => const [
  OnboardingPillar(
    eyebrow: 'Pilar 1',
    isAvailable: true,
    amount: Money.fromMinor(124050),
    headline: 'Anote em três toques. Veja o mês inteiro.',
    lede:
        'Valor, categoria, salvar. Data, conta e espaço já vêm preenchidos — '
        'porque o gasto que você não registra é o que some.',
    fragment: _TrackingFragment(),
  ),
  OnboardingPillar(
    eyebrow: 'Pilar 2',
    isAvailable: false,
    amount: Money.fromMinor(140000),
    isIncomeAmount: true,
    headline: 'Guardar deixa de ser o que sobra.',
    lede:
        'Você define a meta, o app reconhece a contribuição quando ela '
        'acontece e mostra o quanto falta. Sem planilha paralela.',
    fragment: _SavingsSketch(),
  ),
  OnboardingPillar(
    eyebrow: 'Pilar 3',
    isAvailable: false,
    amount: Money.fromMinor(6130),
    headline: 'Dividir a conta sem dever explicação.',
    lede:
        'Um espaço compartilhado mostra quem pagou o quê e quanto cada um '
        'deve. A conversa deixa de ser sobre memória.',
    fragment: _SplitSketch(),
  ),
];

/// Fragmento do pilar 1: linhas reais da lista de transações.
///
/// Usa `TransactionTile` de propósito. Se a linha mudar no design system, a
/// apresentação muda com ela — é o oposto de uma captura de tela que envelhece.
class _TrackingFragment extends StatelessWidget {
  const _TrackingFragment();

  @override
  Widget build(BuildContext context) => _FragmentCard(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(child: Text('Hoje', style: context.texts.labelSmall)),
              const MoneyText(Money.fromMinor(-14280), size: MoneySize.small),
            ],
          ),
        ),
        const _FragmentDivider(),
        const TransactionTile(
          description: 'Mercado São Jorge',
          amount: Money.fromMinor(-9840),
          icon: Icons.restaurant_outlined,
          categoryId: 'onboarding-food',
          // Matiz explícita: sem ela o hash do id sorteia a cor, e a
          // apresentação sairia diferente do desenho aprovado.
          categoryColorIndex: 0,
          meta: 'Alimentação',
        ),
        const _FragmentDivider(),
        const TransactionTile(
          description: 'Transporte',
          amount: Money.fromMinor(-4440),
          icon: Icons.directions_bus_outlined,
          categoryId: 'onboarding-transport',
          categoryColorIndex: 1,
        ),
        const _FragmentDivider(),
        // Receita com `+` e cor de marca: a regra de dinheiro do sistema é
        // demonstrada nos primeiros dez segundos, em vez de explicada depois.
        const TransactionTile(
          description: 'Salário',
          amount: Money.fromMinor(540000),
          icon: Icons.payments_outlined,
          meta: 'Receita',
          isIncome: true,
        ),
      ],
    ),
  );
}

/// Fragmento do pilar 2 — **esboço**, não especificação da tela de metas.
class _SavingsSketch extends StatelessWidget {
  const _SavingsSketch();

  @override
  Widget build(BuildContext context) => _FragmentCard(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reserva de emergência', style: context.texts.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            r'R$ 1.400 de R$ 3.000',
            style: AppTypography.money.copyWith(
              fontSize: 13,
              color: context.tokens.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: 0.47,
              backgroundColor: context.tokens.surfaceSunken,
              valueColor: AlwaysStoppedAnimation(context.colors.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text('47%', style: context.texts.bodySmall),
              ),
              Text(
                r'faltam R$ 1.600',
                style: context.texts.bodySmall?.copyWith(
                  color: context.tokens.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Fragmento do pilar 3 — **esboço**, não especificação da tela de divisão.
class _SplitSketch extends StatelessWidget {
  const _SplitSketch();

  @override
  Widget build(BuildContext context) => _FragmentCard(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Jantar de sábado', style: context.texts.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            r'R$ 183,90 · 3 pessoas',
            style: AppTypography.money.copyWith(
              fontSize: 13,
              color: context.tokens.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final initial in ['G', 'M', 'R'])
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _Avatar(initial: initial),
                ),
              const Spacer(),
              Text(
                '61,30 cada',
                style: AppTypography.money.copyWith(
                  fontSize: 13,
                  color: context.tokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: context.tokens.hairline),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text('Sua parte', style: context.texts.titleSmall),
              ),
              const MoneyText(Money.fromMinor(-6130), size: MoneySize.small),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    width: 26,
    decoration: BoxDecoration(
      color: context.tokens.brandSubtle,
      shape: BoxShape.circle,
      border: Border.all(color: context.tokens.brandBorder),
    ),
    child: Center(
      child: Text(
        initial,
        style: context.texts.labelSmall?.copyWith(
          color: context.tokens.brandText,
          letterSpacing: 0,
        ),
      ),
    ),
  );
}

/// Cartão do fragmento, **cortado à esquerda**.
///
/// O corte na esquerda é deliberado: sinaliza "isto é um pedaço de uma
/// superfície maior" sem tocar na coluna de valores, que fica à direita. Cortar
/// número seria cortar o conteúdo.
class _FragmentCard extends StatelessWidget {
  const _FragmentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.screenGutter),
    child: Transform.translate(
      offset: const Offset(-AppSpacing.xxxl, 0),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(16),
          ),
          border: Border.all(color: context.tokens.hairline),
          boxShadow: context.tokens.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    ),
  );
}

class _FragmentDivider extends StatelessWidget {
  const _FragmentDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: context.tokens.hairline);
}
