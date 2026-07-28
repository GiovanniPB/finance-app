import 'package:finance/features/auth/data/auth_error_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('authErrorMessage', () {
    test('traduz credencial inválida — o caso que aparecia em inglês', () {
      const e = AuthException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );
      expect(authErrorMessage(e), 'E-mail ou senha incorretos.');
    });

    test('traduz e-mail não confirmado', () {
      const e = AuthException(
        'Email not confirmed',
        code: 'email_not_confirmed',
      );
      expect(authErrorMessage(e), contains('Confirme seu e-mail'));
    });

    test('trata e-mail já cadastrado pelos dois códigos do Supabase', () {
      const jaExiste = AuthException('...', code: 'user_already_exists');
      const emailExiste = AuthException('...', code: 'email_exists');
      expect(authErrorMessage(jaExiste), authErrorMessage(emailExiste));
      expect(authErrorMessage(jaExiste), contains('Já existe uma conta'));
    });

    test('traduz senha fraca sem repetir a regra de 6 caracteres da tela', () {
      const e = AuthException(
        'Password should be at least 6 characters',
        code: 'weak_password',
      );
      final message = authErrorMessage(e);
      expect(message, contains('senha'));
      expect(message, isNot(contains('Password')));
    });

    test('traduz excesso de tentativas', () {
      const porRequisicao = AuthException(
        '...',
        code: 'over_request_rate_limit',
      );
      const porEmail = AuthException('...', code: 'over_email_send_rate_limit');
      expect(authErrorMessage(porRequisicao), contains('tentativas'));
      expect(authErrorMessage(porEmail), contains('tentativas'));
    });

    test('traduz sessão expirada nos três códigos que a descrevem', () {
      for (final code in [
        'session_expired',
        'session_missing',
        'session_not_found',
      ]) {
        expect(
          authErrorMessage(AuthException('...', code: code)),
          contains('sessão expirou'),
          reason: 'código $code',
        );
      }
    });

    test('falha de rede vira recado sobre conexão, não sobre credencial', () {
      final e = AuthRetryableFetchException();
      expect(authErrorMessage(e), contains('conexão'));
    });

    test(
      'código desconhecido cai no genérico em português, nunca no texto cru',
      () {
        const e = AuthException(
          'Some brand new English error',
          code: 'a_code_that_does_not_exist_yet',
        );
        final message = authErrorMessage(e);
        expect(message, isNot(contains('English')));
        expect(
          message,
          'Não foi possível concluir a autenticação. '
          'Tente de novo em instantes.',
        );
      },
    );

    test('exceção sem código também cai no genérico', () {
      const e = AuthException('Something failed');
      expect(authErrorMessage(e), isNot(contains('Something')));
    });

    test('toda mensagem termina em ponto e começa em maiúscula', () {
      const codes = [
        'invalid_credentials',
        'email_not_confirmed',
        'user_already_exists',
        'weak_password',
        'over_request_rate_limit',
        'session_expired',
        'user_not_found',
        'signup_disabled',
        'user_banned',
        'validation_failed',
        'captcha_failed',
        'email_provider_disabled',
        'desconhecido',
      ];
      for (final code in codes) {
        final message = authErrorMessage(AuthException('x', code: code));
        expect(message.endsWith('.'), isTrue, reason: '$code: "$message"');
        expect(
          message[0],
          message[0].toUpperCase(),
          reason: '$code: "$message"',
        );
      }
    });
  });
}
