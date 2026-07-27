import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/space_home_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../savings/presentation/goal_icons.dart';
import '../../savings/presentation/savings_page.dart';
import '../../spaces/presentation/spaces_page.dart';
import '../../transactions/presentation/quick_entry_sheet.dart';

/// Shell da aplicação: as quatro abas do PRD §11.1 mais a ação central.
///
/// A ação central (`+`) **não é uma aba** — abre o registro rápido como bottom
/// sheet. É a porta da promessa dos 30 segundos e precisa estar a um toque de
/// qualquer aba.
///
/// Usa [IndexedStack] em vez de rotas aninhadas: preserva o estado de cada aba
/// e mantém a Fase 0 simples. A contrapartida é que as abas não têm URL
/// própria — quando deep link por aba virar requisito, isto vira
/// `StatefulShellRoute`.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  /// A terceira aba se chama **Poupança**, e não "Social" como previa o mapa de
  /// navegação do PRD (§11.1): ela é a entrada do Pilar 3, e o que existe dele
  /// hoje são metas. Feed, amigos e desafios são Fase 3 — um rótulo que promete
  /// o que não existe é justamente o que os pilares 2 e 3 do onboarding evitam
  /// de propósito. Quando a camada social chegar, ela entra nesta mesma aba.
  static const _destinations = [
    AppNavDestination(icon: Icons.home_outlined, label: 'Início'),
    AppNavDestination(icon: Icons.workspaces_outline, label: 'Espaços'),
    AppNavDestination(icon: GoalIcons.tab, label: 'Poupança'),
    AppNavDestination(icon: Icons.person_outline, label: 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: IndexedStack(
        index: _index,
        children: const [
          SpaceHomePage(),
          SpacesPage(),
          SavingsPage(),
          ProfilePage(),
        ],
      ),
    ),
    bottomNavigationBar: AppBottomNav(
      destinations: _destinations,
      currentIndex: _index,
      onSelected: (index) => setState(() => _index = index),
      onCentralAction: () => QuickEntrySheet.show(context),
    ),
  );
}
