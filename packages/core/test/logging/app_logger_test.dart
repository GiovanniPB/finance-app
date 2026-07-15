import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('AppLogger.redact', () {
    test('mascara valores no formato chave=valor', () {
      expect(AppLogger.redact('token=abc123 outro=ok'), 'token=*** outro=ok');
      expect(
        AppLogger.redact('password=hunter2'),
        'password=***',
      );
    });

    test('mascara valores em JSON', () {
      expect(
        AppLogger.redact('{"access_token": "xyz", "user": "ana"}'),
        '{"access_token": "***", "user": "ana"}',
      );
    });

    test('é case-insensitive', () {
      expect(AppLogger.redact('Authorization=Bearer_zzz'), 'Authorization=***');
    });

    test('preserva texto sem chaves sensíveis', () {
      expect(AppLogger.redact('carregando contas'), 'carregando contas');
    });
  });

  group('AppLogger', () {
    test('todos os níveis emitem registros redigidos', () {
      final records = <LogRecord>[];
      AppLogger.configure(level: Level.ALL, onRecord: records.add);

      final log = AppLogger('Levels')
        ..fine('password=abc')
        ..info('ok')
        ..warning('token=xyz', Exception('boom'), StackTrace.current)
        ..severe('secret=zzz', Exception('fatal'), StackTrace.current);

      expect(records, hasLength(4));
      expect(records[0].message, 'password=***');
      expect(records[2].message, 'token=***');
      expect(records[2].error, isA<Exception>());
      expect(records[3].message, 'secret=***');
      expect(log, isNotNull);
    });

    test('configure instala listener único e emite registros', () {
      final records = <LogRecord>[];
      AppLogger.configure(level: Level.ALL, onRecord: records.add);

      AppLogger('Test').info('token=segredo123');

      expect(records, hasLength(1));
      expect(records.single.message, 'token=***');
      expect(records.single.loggerName, 'Test');

      // Idempotente: reconfigurar não duplica listeners.
      final again = <LogRecord>[];
      AppLogger.configure(level: Level.ALL, onRecord: again.add);
      AppLogger('Test').warning('ok');
      expect(records, hasLength(1));
      expect(again, hasLength(1));
    });
  });
}
