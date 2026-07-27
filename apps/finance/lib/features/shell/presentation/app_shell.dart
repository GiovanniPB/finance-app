import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/space_home_page.dart';
import '../../profile/presentation/profile_page.dart';
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

  static const _destinations = [
    AppNavDestination(icon: Icons.home_outlined, label: 'Início'),
    AppNavDestination(icon: Icons.workspaces_outline, label: 'Espaços'),
    AppNavDestination(icon: Icons.people_outline, label: 'Social'),
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
          _ComingSoon(
            icon: Icons.people_outline,
            title: 'Social',
            message:
                'Amigos, desafios e feed de progresso chegam depois que o '
                'registro individual estiver redondo.',
          ),
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

/// Placeholder honesto para as abas de fases futuras.
///
/// Diz o que vai existir e por que ainda não existe, em vez de mostrar uma tela
/// vazia sem explicação.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.screenGutter),
    child: Center(
      child: AppEmptyState(icon: icon, title: title, message: message),
    ),
  );
}
