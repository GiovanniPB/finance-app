import 'package:flutter/widgets.dart';

/// Placeholders temporários — a UI real será construída em fases posteriores.
/// Existem apenas para o roteamento e o guard de auth compilarem e serem
/// testáveis nesta fase headless.
class HomePlaceholderPage extends StatelessWidget {
  const HomePlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Home (placeholder)'));
}

class SignInPlaceholderPage extends StatelessWidget {
  const SignInPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Sign in (placeholder)'));
}
