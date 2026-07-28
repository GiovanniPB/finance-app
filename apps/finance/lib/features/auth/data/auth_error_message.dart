import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduz a falha do Supabase Auth para uma frase em português.
///
/// Por que existe: o `message` que o SDK entrega é escrito em inglês pelo
/// servidor do Supabase, e ele ia **cru** para a tela de login — "Invalid login
/// credentials" no meio de um app em português. Nenhuma revisão de código pega
/// isso, porque o texto não está no repo; só rodando é que aparece.
///
/// Casa por `code`, não por `message`. O código é contrato de API e a frase é
/// texto livre que muda entre versões do servidor — casar por texto quebraria
/// numa atualização sem nada no repo mudar. Os códigos vêm de
/// https://supabase.com/docs/guides/auth/debugging/error-codes.
///
/// **Deliberadamente não usa o enum `ErrorCode` do gotrue**: a versão 2.26.0
/// não lista `invalid_credentials` — justamente o caso mais comum — então
/// depender do enum deixaria o erro principal cair no genérico. String crua
/// mantém a tradução independente da completude de uma lista de terceiros.
///
/// Código desconhecido cai no genérico em vez de mostrar o inglês. Não se perde
/// diagnóstico: `AuthRepositoryImpl` já registra a exceção original no
/// `AppLogger` antes de chamar esta função.
String authErrorMessage(AuthException exception) {
  // Falha de rede não tem `code` (a resposta nunca chegou), e é o único caso em
  // que o tipo da exceção diz mais que o código.
  if (exception is AuthRetryableFetchException) {
    return 'Sem conexão com o servidor. '
        'Verifique sua internet e tente de novo.';
  }

  return switch (exception.code) {
    'invalid_credentials' => 'E-mail ou senha incorretos.',
    'email_not_confirmed' || 'phone_not_confirmed' =>
      'Confirme seu e-mail antes de entrar. '
          'Procure a mensagem que enviamos para você.',
    'user_already_exists' ||
    'email_exists' ||
    'phone_exists' => 'Já existe uma conta com este e-mail. Tente entrar.',
    // A tela já exige 6 caracteres; se o servidor recusou, a política dele é
    // mais estrita que a nossa — daí a frase pedir uma senha mais forte em vez
    // de repetir um número que pode não ser o que barrou.
    'weak_password' =>
      'Essa senha é fraca demais. Escolha uma senha mais longa, '
          'misturando letras e números.',
    'user_not_found' => 'Não encontramos uma conta com este e-mail.',
    'over_request_rate_limit' ||
    'over_email_send_rate_limit' ||
    'over_sms_send_rate_limit' =>
      'Muitas tentativas em pouco tempo. '
          'Espere um instante e tente de novo.',
    'session_expired' ||
    'session_missing' ||
    'session_not_found' => 'Sua sessão expirou. Entre de novo.',
    'signup_disabled' || 'anonymous_provider_disabled' =>
      'O cadastro está desativado neste momento.',
    'email_provider_disabled' || 'provider_disabled' =>
      'A entrada por e-mail e senha está desativada neste momento.',
    'user_banned' => 'Esta conta está suspensa.',
    'validation_failed' ||
    'bad_json' => 'Confira o e-mail e a senha digitados.',
    'captcha_failed' =>
      'Não foi possível confirmar que você não é um robô. Tente de novo.',
    'same_password' => 'A nova senha é igual à atual.',
    'request_timeout' => 'O servidor demorou para responder. Tente de novo.',
    _ =>
      'Não foi possível concluir a autenticação. '
          'Tente de novo em instantes.',
  };
}
