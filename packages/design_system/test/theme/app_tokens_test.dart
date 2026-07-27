import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTokens — semântica de dinheiro', () {
    test('despesa é o texto primário, não uma cor própria', () {
      // A regra central: despesa é o estado neutro. Se algum dia moneyNeutral
      // divergir do texto primário, a regra foi quebrada.
      expect(AppTokens.light().moneyNeutral, AppPalette.ink900);
      expect(AppTokens.dark().moneyNeutral, AppPalette.darkInk);
    });

    test('receita usa a cor da marca em ambos os temas', () {
      expect(AppTokens.light().moneyPositive, AppPalette.teal600);
      expect(AppTokens.dark().moneyPositive, AppPalette.teal300);
    });

    test('vermelho fica reservado a estourado/erro', () {
      expect(AppTokens.light().moneyOver, AppPalette.red600);
      expect(AppTokens.dark().moneyOver, AppPalette.redDark);
      // E nunca é o tom de despesa.
      expect(
        AppTokens.light().moneyNeutral,
        isNot(AppTokens.light().moneyOver),
      );
    });
  });

  group('AppTokens — elevação', () {
    test('o claro tem sombra', () {
      expect(AppTokens.light().cardShadow, isNotEmpty);
      expect(AppTokens.light().microShadow, isNotEmpty);
    });

    test('o escuro não tem sombra nenhuma', () {
      // Decisão deliberada: sombra não se lê em canvas quase preto. A
      // profundidade vem dos degraus de superfície.
      expect(AppTokens.dark().cardShadow, isEmpty);
      expect(AppTokens.dark().microShadow, isEmpty);
    });
  });

  group('AppTokens — paleta de categorias', () {
    test('tem seis matizes', () {
      expect(AppTokens.light().categoryPalette, hasLength(6));
      expect(AppTokens.dark().categoryPalette, hasLength(6));
    });

    test('a cor de uma categoria é estável para o mesmo id', () {
      final tokens = AppTokens.light();
      final first = tokens.colorsForCategory('alimentacao');
      final second = tokens.colorsForCategory('alimentacao');

      expect(first, second);
    });

    test('ids diferentes podem receber matizes diferentes', () {
      final tokens = AppTokens.light();
      final colors = {
        for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g'])
          tokens.colorsForCategory(id),
      };

      // Com 7 ids e 6 matizes há colisão por definição; o que importa é que
      // não colapse tudo numa cor só.
      expect(colors.length, greaterThan(1));
    });

    test('o índice nunca sai da faixa da paleta', () {
      final tokens = AppTokens.light();
      for (final id in ['', 'x', 'id-muito-longo-com-acentuação-é', '123']) {
        expect(() => tokens.colorsForCategory(id), returnsNormally);
      }
    });
  });

  group('AppTokens — copyWith e lerp', () {
    test('copyWith sem argumentos preserva tudo', () {
      final tokens = AppTokens.light();
      final copy = tokens.copyWith();

      expect(copy.moneyNeutral, tokens.moneyNeutral);
      expect(copy.moneyPositive, tokens.moneyPositive);
      expect(copy.categoryPalette, tokens.categoryPalette);
      expect(copy.cardShadow, tokens.cardShadow);
    });

    test('copyWith substitui só o campo informado', () {
      final tokens = AppTokens.light();
      final copy = tokens.copyWith(moneyPositive: const Color(0xFF00FF00));

      expect(copy.moneyPositive, const Color(0xFF00FF00));
      expect(copy.moneyNeutral, tokens.moneyNeutral);
    });

    test('lerp com null devolve a própria instância', () {
      final tokens = AppTokens.light();
      expect(tokens.lerp(null, 0.5), same(tokens));
    });

    test('lerp em t=0 e t=1 chega nos extremos', () {
      final light = AppTokens.light();
      final dark = AppTokens.dark();

      expect(light.lerp(dark, 0).moneyPositive, light.moneyPositive);
      expect(light.lerp(dark, 1).moneyPositive, dark.moneyPositive);
    });

    test('lerp interpola a cor no meio do caminho', () {
      final light = AppTokens.light();
      final dark = AppTokens.dark();
      final mid = light.lerp(dark, 0.5);

      expect(mid.moneyPositive, isNot(light.moneyPositive));
      expect(mid.moneyPositive, isNot(dark.moneyPositive));
    });

    test('lerp troca a sombra no meio, sem interpolar lista vazia', () {
      final light = AppTokens.light();
      final dark = AppTokens.dark();

      expect(light.lerp(dark, 0.2).cardShadow, isNotEmpty);
      expect(light.lerp(dark, 0.8).cardShadow, isEmpty);
    });

    test('lerp da paleta preserva o número de matizes', () {
      final mid = AppTokens.light().lerp(AppTokens.dark(), 0.5);
      expect(mid.categoryPalette, hasLength(6));
    });

    test('lerp da paleta cai no degrau quando os tamanhos diferem', () {
      final light = AppTokens.light();
      final shorter = light.copyWith(
        categoryPalette: [light.categoryPalette.first],
      );

      expect(light.lerp(shorter, 0.2).categoryPalette, hasLength(6));
      expect(light.lerp(shorter, 0.8).categoryPalette, hasLength(1));
    });
  });

  group('CategoryColors', () {
    test('igualdade por valor', () {
      const a = CategoryColors(fill: Color(0xFF111111), ink: Color(0xFF222222));
      const b = CategoryColors(fill: Color(0xFF111111), ink: Color(0xFF222222));
      const c = CategoryColors(fill: Color(0xFF333333), ink: Color(0xFF222222));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('lerp interpola os dois canais', () {
      const a = CategoryColors(fill: Color(0xFF000000), ink: Color(0xFF000000));
      const b = CategoryColors(fill: Color(0xFFFFFFFF), ink: Color(0xFFFFFFFF));
      final mid = CategoryColors.lerp(a, b, 0.5);

      expect(mid.fill, isNot(a.fill));
      expect(mid.fill, isNot(b.fill));
      expect(mid.ink, mid.fill);
    });
  });
}
