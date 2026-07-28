import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/savings_streak.dart';
import 'streak_copy.dart';

/// A sequência de semanas, na aba Poupança (RN-3.4).
///
/// Fica **abaixo** do total guardado, não no lugar dele: o momento alto da tela
/// continua sendo quanto se tem: o streak é a leitura do hábito, que responde
/// outra pergunta ("estou mantendo?") e não deve competir com o número grande.
///
/// **Sem sequência viva, o bloco fica neutro e discreto** — mesma superfície de
/// poço do aporte pendente. Só uma sequência viva ganha a marca, e é a única
/// coisa da tela que o faz além da meta concluída: o realce é o prêmio, e
/// distribuí-lo pelo estado vazio o gastaria à toa.
///
/// Nenhum estado usa âmbar ou vermelho. Ver a doc de [StreakCopy] para o
/// porquê.
class StreakBanner extends StatelessWidget {
  const StreakBanner({required this.streak, super.key});

  final SavingsStreak streak;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final active = streak.isActive;

    return Container(
      key: const Key('streak_banner'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: active ? tokens.brandSubtle : tokens.surfaceSunken,
        borderRadius: AppRadii.brLg,
        border: active ? Border.all(color: tokens.brandBorder) : null,
      ),
      child: Row(
        children: [
          Icon(
            active
                ? Icons.local_fire_department
                : Icons.local_fire_department_outlined,
            color: active ? tokens.brandText : tokens.textMuted,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  StreakCopy.title(streak),
                  style: context.texts.titleSmall?.copyWith(
                    color: active ? tokens.brandText : tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  StreakCopy.caption(streak),
                  style: context.texts.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
