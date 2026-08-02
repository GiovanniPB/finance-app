import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/domain/account.dart';
import '../../accounts/presentation/account_form_sheet.dart';
import '../../accounts/presentation/account_tile.dart';
import '../../accounts/presentation/accounts_providers.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/categories_providers.dart';
import '../../categories/presentation/category_form_sheet.dart';
import '../../categories/presentation/category_icons.dart';
import '../../open_finance/domain/open_finance_connection.dart';
import '../../open_finance/presentation/connect_bank_page.dart';
import '../../open_finance/presentation/connection_sheet.dart';
import '../../open_finance/presentation/connection_tile.dart';
import '../../open_finance/presentation/open_finance_providers.dart';
import 'profile_name_sheet.dart';
import 'profile_providers.dart';

/// Aba Perfil (PRD §11.1).
///
/// Hoje é a casa das **contas**: onde o dinheiro fica. Assinatura e
/// preferências entram aqui nas fases seguintes — o placeholder que existia
/// nesta aba já prometia isso, e a promessa continua visível em vez de sumir.
///
/// As contas moram aqui, e não numa aba própria, porque cadastrar conta é algo
/// que se faz uma vez e se revisita raramente: não compete com registrar gasto,
/// que é diário.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(accountsProvider).asData?.value ?? const <Account>[];
    final net = ref.watch(accountsNetBalanceProvider);
    final userCategories = ref.watch(userCategoriesProvider);
    final connections =
        ref.watch(openFinanceConnectionsProvider).asData?.value ??
        const <OpenFinanceConnection>[];
    final accountCounts = ref.watch(connectionAccountCountsProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            AppSpacing.lg,
          ),
          child: Text('Perfil', style: context.texts.displaySmall),
        ),
        const _SectionHeader(title: 'Você'),
        const _YouTile(),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            AppSpacing.lg,
          ),
          child: Divider(height: 1),
        ),
        _SectionHeader(
          title: 'Contas',
          // O total só aparece quando há conta e todas na mesma moeda —
          // ver `accountsNetBalanceProvider`.
          trailing: net == null ? null : _NetBalance(amount: net),
        ),
        if (accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: AppEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Nenhuma conta cadastrada',
              message:
                  'Cadastre onde seu dinheiro fica para saber com quanto você '
                  'conta — e para as metas de poupança terem um destino.',
              actionLabel: 'Nova conta',
              onAction: () => AccountFormSheet.show(context),
            ),
          )
        else ...[
          for (final account in accounts)
            AccountTile(
              key: Key('account_${account.id}'),
              account: account,
              onTap: () => AccountFormSheet.show(context, editing: account),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              0,
            ),
            child: AppButton(
              key: const Key('new_account'),
              label: 'Nova conta',
              variant: AppButtonVariant.secondary,
              icon: Icons.add,
              onPressed: () => AccountFormSheet.show(context),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        const _SectionHeader(title: 'Bancos conectados'),
        if (connections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: AppEmptyState(
              key: const Key('no_connections'),
              icon: Icons.account_balance_outlined,
              title: 'Nenhum banco conectado',
              message:
                  'Conectar seu banco traz os lançamentos sem você digitar. '
                  'Suas credenciais ficam no provedor de Open Finance — o app '
                  'nunca as vê.',
              actionLabel: 'Conectar banco',
              onAction: () => ConnectBankPage.show(context),
            ),
          )
        else ...[
          for (final connection in connections)
            ConnectionTile(
              key: Key('connection_${connection.id}'),
              connection: connection,
              accountCount: accountCounts[connection.id] ?? 0,
              // Toda conexão responde ao toque, e o que ela abre é a folha de
              // ações. Antes só a que pedia re-consentimento respondia, o que
              // deixava a linha saudável inerte — e não havia lugar nenhum para
              // "Remover banco", que existia no repository e em nenhuma tela.
              onTap: () => ConnectionSheet.show(
                context,
                connection: connection,
                accountCount: accountCounts[connection.id] ?? 0,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              0,
            ),
            child: AppButton(
              key: const Key('connect_bank'),
              label: 'Conectar outro banco',
              variant: AppButtonVariant.secondary,
              icon: Icons.add,
              onPressed: () => ConnectBankPage.show(context),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        const _SectionHeader(title: 'Suas categorias'),
        if (userCategories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            child: Text(
              'As dez categorias do sistema cobrem o básico. As que você criar '
              'aparecem aqui, para renomear ou remover.',
              key: const Key('no_user_categories'),
              style: context.texts.bodySmall?.copyWith(
                color: context.tokens.textMuted,
              ),
            ),
          )
        else
          for (final category in userCategories)
            _CategoryTile(
              key: Key('category_${category.id}'),
              category: category,
              onTap: () => CategoryFormSheet.show(context, editing: category),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            0,
          ),
          child: AppButton(
            key: const Key('new_category'),
            label: 'Nova categoria',
            variant: AppButtonVariant.secondary,
            icon: Icons.add,
            onPressed: () => CategoryFormSheet.show(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const _SectionHeader(title: 'Ainda não'),
        const Padding(
          padding: EdgeInsets.all(AppSpacing.screenGutter),
          child: AppEmptyState(
            icon: Icons.workspace_premium_outlined,
            title: 'Assinatura e preferências',
            message:
                'Plano, notificações e dados da conta chegam junto com as '
                'fases de Open Finance e colaboração.',
          ),
        ),
      ],
    );
  }
}

/// Uma categoria de usuário na lista do Perfil.
///
/// Espelha a `AccountTile` de propósito: mesma altura de toque, mesmo swatch da
/// linha de transação, mesma hairline. A seção é de gerenciamento, e duas
/// listas de gerenciamento na mesma tela com formas diferentes leriam como duas
/// telas.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onTap,
    super.key,
  });

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              CategorySwatch(
                categoryId: category.id,
                colorIndex: category.colorIndex,
                icon: CategoryIcons.resolve(category.iconKey),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(category.name, style: context.texts.bodyMedium),
              ),
              Icon(Icons.chevron_right, size: 18, color: tokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A linha "Você": o nome, e o convite para defini-lo.
///
/// Três estados, e os três importam:
///
///  * **Sem a linha de `profiles`** — ela chega pelo bucket `user_owned`, e
///    antes disso não há o que editar. A linha não é tocável de propósito: um
///    `UPDATE` sem linha afeta zero e **não dá erro**, então abrir a folha aqui
///    terminaria em "salvo" sem nada salvo.
///  * **Sem nome** — convite, não vazio mudo. `AppEmptyState` não serve: isto é
///    uma linha, não uma seção vazia.
///  * **Com nome** — o nome, e a frase que diz para que ele serve. Sem ela o
///    campo parece vaidade, e ninguém preenche.
class _YouTile extends ConsumerWidget {
  const _YouTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final profile = ref.watch(myProfileProvider).asData?.value;

    if (profile == null) {
      return const _YouTileSkeleton();
    }

    final name = profile.displayName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('profile_you_tile'),
        onTap: () => ProfileNameSheet.show(context, profile: profile),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
            vertical: AppSpacing.md,
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
                      name ?? 'Defina seu nome',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall?.copyWith(
                        color: name == null ? tokens.textMuted : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      name == null
                          ? 'Enquanto não tiver, quem divide um espaço com '
                                'você vê só o seu papel'
                          : 'É assim que você aparece para quem divide um '
                                'espaço com você',
                      style: context.texts.bodySmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right, size: 20, color: tokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// O estado de espera, com a forma da linha que vai chegar.
///
/// Duas barras em vez de um spinner: a seção tem tamanho conhecido, e um
/// spinner faria a lista pular quando o perfil chegasse.
class _YouTileSkeleton extends StatelessWidget {
  const _YouTileSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    Widget bar(double width, double height) => DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: AppRadii.brSm,
      ),
      child: SizedBox(height: height, width: width),
    );

    return Padding(
      key: const Key('profile_you_skeleton'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          const CategorySwatch.brand(icon: Icons.person_outline),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(140, 13),
              const SizedBox(height: AppSpacing.xs),
              bar(96, 10),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      0,
      AppSpacing.screenGutter,
      AppSpacing.sm,
    ),
    child: Row(
      children: [
        Expanded(child: Text(title, style: context.texts.titleMedium)),
        ?trailing,
      ],
    ),
  );
}

/// Soma das contas, com o rótulo dizendo o que ela é.
///
/// "Total" sozinho seria ambíguo com o saldo do mês que a Home mostra; aqui é
/// o que existe nas contas, com a fatura de cartão já descontada.
class _NetBalance extends StatelessWidget {
  const _NetBalance({required this.amount});

  final Money amount;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Nas contas',
        style: context.texts.bodySmall?.copyWith(
          color: context.tokens.textMuted,
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      // Neutro pelo mesmo motivo da linha da conta: dever no cartão é estado
      // ordinário, não alarme. Ver o comentário em `AccountTile`.
      MoneyText(
        amount,
        key: const Key('accounts_net_balance'),
        withSymbol: true,
      ),
    ],
  );
}
