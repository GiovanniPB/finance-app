import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Um destino da [AppBottomNav].
@immutable
class AppNavDestination {
  const AppNavDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Bottom nav do app (PRD §11.1).
///
/// Quatro destinos mais uma **ação central** destacada, que abre o registro
/// rápido. A ação central não é um destino — não tem estado selecionado —
/// porque é a porta dos 30 segundos e fica sempre a um toque.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    required this.onCentralAction,
    this.centralIcon = Icons.add,
    super.key,
  });

  /// Destinos, em ordem. A ação central é inserida no meio da lista.
  final List<AppNavDestination> destinations;

  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// Chamado ao tocar a ação central (registro rápido).
  final VoidCallback onCentralAction;

  final IconData centralIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final half = destinations.length ~/ 2;

    // A nav tem altura fixa, então texto muito ampliado a estouraria. Limitar
    // a escala aqui (em vez de ignorá-la) mantém a barra legível sem quebrar o
    // layout — o resto do app continua respeitando a escala do usuário.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        height: AppSizes.bottomNav,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          border: Border(top: BorderSide(color: tokens.hairline)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < half; i++)
              _NavItem(
                destination: destinations[i],
                isSelected: i == currentIndex,
                onTap: () => onSelected(i),
              ),
            _CentralAction(icon: centralIcon, onTap: onCentralAction),
            for (var i = half; i < destinations.length; i++)
              _NavItem(
                destination: destinations[i],
                isSelected: i == currentIndex,
                onTap: () => onSelected(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = isSelected ? tokens.brandText : tokens.textMuted;

    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: AppSizes.touchTarget,
          child: Column(
            // mainAxisSize.min + Center: a coluna mede o conteúdo e é
            // centrada, em vez de tentar preencher e estourar por 1-2px.
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(destination.icon, size: 20, color: color),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall?.copyWith(
                    color: color,
                    fontSize: 10,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CentralAction extends StatelessWidget {
  const _CentralAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Registrar',
      child: InkWell(
        onTap: onTap,
        customBorder: const RoundedRectangleBorder(
          borderRadius: AppRadii.brLg,
        ),
        child: Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: context.colors.primary,
            borderRadius: AppRadii.brLg,
            boxShadow: context.tokens.microShadow,
          ),
          child: Center(
            child: Icon(icon, size: 22, color: context.colors.onPrimary),
          ),
        ),
      ),
    );
  }
}
