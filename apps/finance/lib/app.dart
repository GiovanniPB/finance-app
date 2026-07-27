import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';

/// Raiz da aplicação: tema, localização e roteamento.
class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key});

  /// Único idioma suportado. O produto é do mercado brasileiro (PRD §1) e todo
  /// texto do app é escrito em português direto no código — não há camada de
  /// tradução, e declarar um segundo idioma prometeria o que não existe.
  static const locale = Locale('pt', 'BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'Finance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Sem isto, todo widget do Material que traz texto próprio sai em inglês
      // no meio de um app em português: o seletor de data do prazo da meta
      // aparecia como "Fri, Jan 1 / January 2027 / Cancel / OK". O texto vem do
      // Flutter, não do app, então nenhuma revisão de código nossa o pegaria —
      // só rodar e olhar.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [locale],
      locale: locale,
      routerConfig: router,
    );
  }
}
