import 'dart:developer' as developer;

import 'package:logging/logging.dart';

/// Fina camada sobre `package:logging` com redação de dados sensíveis.
///
/// Uso: `final log = AppLogger('AuthRepository');` e então `log.info(...)`.
/// Configure uma vez no boot com [AppLogger.configure].
class AppLogger {
  AppLogger(String name) : _logger = Logger(name);

  final Logger _logger;

  /// Chaves cujos valores devem ser mascarados em qualquer mensagem logada.
  static const _sensitiveKeys = <String>[
    'password',
    'token',
    'access_token',
    'refresh_token',
    'anon_key',
    'apikey',
    'api_key',
    'authorization',
    'secret',
  ];

  /// Instala um handler único no root logger. Idempotente.
  ///
  /// O sink padrão usa `dart:developer` (visível no DevTools e nos logs
  /// nativos, e seguro em web). Em produção, injete [onRecord] apontando para
  /// um transporte (Crashlytics/Sentry).
  static void configure({
    Level level = Level.INFO,
    void Function(LogRecord)? onRecord,
  }) {
    Logger.root.level = level;
    Logger.root.clearListeners();
    Logger.root.onRecord.listen(
      onRecord ??
          (record) => developer.log(
            record.message,
            time: record.time,
            level: record.level.value,
            name: record.loggerName,
            error: record.error,
            stackTrace: record.stackTrace,
          ),
    );
  }

  /// Mascara valores associados a chaves sensíveis em [input].
  ///
  /// Reconhece padrões `chave=valor` e `"chave": "valor"` (case-insensitive).
  static String redact(String input) {
    var output = input;
    for (final key in _sensitiveKeys) {
      // chave=valor  ->  chave=***
      output = output.replaceAllMapped(
        RegExp('$key=[^\\s,;&]+', caseSensitive: false),
        (m) => '${_keyOf(m[0]!, '=')}=***',
      );
      // "chave": "valor"  ->  "chave": "***"
      output = output.replaceAllMapped(
        RegExp('("?$key"?\\s*:\\s*)"[^"]*"', caseSensitive: false),
        (m) => '${m[1]}"***"',
      );
    }
    return output;
  }

  static String _keyOf(String match, String separator) =>
      match.substring(0, match.indexOf(separator));

  void fine(String message) => _logger.fine(redact(message));

  void info(String message) => _logger.info(redact(message));

  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.warning(redact(message), error, stackTrace);

  void severe(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.severe(redact(message), error, stackTrace);
}
