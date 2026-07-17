import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';
import '../../spaces/presentation/spaces_providers.dart';

/// Home mínima da fase de fundação: mostra o espaço ativo (que só existe se a
/// sincronização trouxe os dados do servidor) e permite sair. Serve para
/// validar o loop offline-first end-to-end.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSpace = ref.watch(activeSpaceProvider);
    final spaces = ref.watch(spacesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Início'),
        actions: [
          IconButton(
            key: const Key('sign_out'),
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Center(
        child: switch (activeSpace) {
          null => const _WaitingSync(),
          final space => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspaces_outline,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text('Espaço ativo', style: theme.textTheme.labelMedium),
              Text(
                space.name,
                key: const Key('active_space_name'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${spaces.asData?.value.length ?? 0} espaço(s) sincronizado(s)',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _WaitingSync extends StatelessWidget {
  const _WaitingSync();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircularProgressIndicator(),
      SizedBox(height: 16),
      Text('Sincronizando seus dados…'),
    ],
  );
}
