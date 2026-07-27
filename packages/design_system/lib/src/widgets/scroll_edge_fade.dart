import 'package:flutter/material.dart';

/// Desvanecimento de 24px no fim de uma rolagem que termina sob uma barra fixa.
///
/// Existe porque um corte seco lê como **defeito de renderização**, não como
/// "há mais coisa abaixo". Meia linha de lista, meio card ou — pior — meio alvo
/// de toque cortado na borda faz o usuário achar que a tela quebrou; o mesmo
/// conteúdo esmaecendo diz que dá para rolar.
///
/// Fica **sobre** o conteúdo e ignora toque ([IgnorePointer]), então não rouba
/// gesto de rolagem na faixa que cobre.
///
/// Uso: como último filho de uma `Column` cujo penúltimo filho é a área de
/// rolagem, com margem negativa; ou dentro de um `Stack` alinhado ao fim.
class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({this.color, this.height = defaultHeight, super.key});

  /// Cor de destino do gradiente. Padrão: o fundo da tela, que é o que está
  /// atrás do conteúdo que se desvanece.
  final Color? color;

  final double height;

  static const defaultHeight = 24.0;

  @override
  Widget build(BuildContext context) {
    final target = color ?? Theme.of(context).scaffoldBackgroundColor;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // `withAlpha(0)` em vez de `Colors.transparent`: transparente é
              // preto com alfa zero, e alguns navegadores/renderizadores
              // interpolam por preto, sujando o meio do gradiente.
              colors: [target.withAlpha(0), target],
            ),
          ),
        ),
      ),
    );
  }
}
