import 'package:meta/meta.dart';

/// Base selada para todas as falhas de domínio recuperáveis.
///
/// Falhas fluem pela aplicação dentro de um `Result`, nunca como exceptions
/// que vazam para a camada de UI. Cada subtipo representa uma categoria de erro
/// tratável de forma distinta pela apresentação.
@immutable
sealed class Failure {
  const Failure(this.message, {this.cause, this.stackTrace});

  /// Mensagem legível, adequada para log e (quando apropriado) para o usuário.
  final String message;

  /// Erro original que causou a falha, quando houver (ex.: exception do SDK).
  final Object? cause;

  /// Stack trace associado à [cause], quando disponível.
  final StackTrace? stackTrace;
}

/// Falha de rede/conectividade (timeout, offline, host inacessível).
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.cause, super.stackTrace});
}

/// Falha de autenticação/autorização (credenciais inválidas, sessão expirada).
final class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.cause, super.stackTrace});
}

/// Falha no banco local (SQLite/PowerSync).
final class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, {super.cause, super.stackTrace});
}

/// Falha no pipeline de sincronização (upload/download, sync rules).
final class SyncFailure extends Failure {
  const SyncFailure(super.message, {super.cause, super.stackTrace});
}

/// Falha de validação de entrada (dados fora das regras de negócio).
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.cause, super.stackTrace});
}

/// Falha inesperada não mapeada — indica lacuna a ser tratada.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.cause, super.stackTrace});
}
