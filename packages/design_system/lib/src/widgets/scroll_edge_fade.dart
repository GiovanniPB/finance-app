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
/// Uso vertical: como último filho de uma `Column` cujo penúltimo filho é a
/// área de rolagem, com margem negativa; ou dentro de um `Stack` alinhado ao
/// fim.
///
/// Uso horizontal ([Axis.horizontal]): num `Stack` alinhado a `centerRight`,
/// sobre uma lista que rola de lado. É o caso da fila de categorias, onde o
/// último chip visível era cortado contra o chip "Nova" ancorado à direita.
class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({
    this.color,
    this.extent = defaultHeight,
    this.axis = Axis.vertical,
    super.key,
  });

  /// Cor de destino do gradiente. Padrão: o fundo da tela, que é o que está
  /// atrás do conteúdo que se desvanece.
  final Color? color;

  /// Espessura da faixa: altura no eixo vertical, largura no horizontal.
  final double extent;

  /// Em que direção o conteúdo rola. É o eixo que decide se a faixa fica em pé
  /// ou deitada, porque o gradiente corre na direção da rolagem.
  final Axis axis;

  static const defaultHeight = 24.0;

  @override
  Widget build(BuildContext context) {
    final target = color ?? Theme.of(context).scaffoldBackgroundColor;
    final isVertical = axis == Axis.vertical;

    return IgnorePointer(
      child: SizedBox(
        height: isVertical ? extent : null,
        width: isVertical ? null : extent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isVertical ? Alignment.topCenter : Alignment.centerLeft,
              end: isVertical ? Alignment.bottomCenter : Alignment.centerRight,
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
