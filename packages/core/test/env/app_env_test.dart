import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  const valid = {
    'FLAVOR': 'staging',
    'SUPABASE_URL': 'https://x.supabase.co',
    'SUPABASE_ANON_KEY': 'anon-key-123',
    'POWERSYNC_URL': 'https://x.powersync.journeyapps.com',
  };

  group('AppEnv.parse', () {
    test('constrói a partir de mapa válido', () {
      final env = AppEnv.parse(valid);
      expect(env.flavor, AppFlavor.staging);
      expect(env.supabaseUrl, 'https://x.supabase.co');
      expect(env.supabaseAnonKey, 'anon-key-123');
      expect(env.powersyncUrl, 'https://x.powersync.journeyapps.com');
    });

    test('usa dev como flavor padrão quando ausente', () {
      final env = AppEnv.parse({...valid}..remove('FLAVOR'));
      expect(env.flavor, AppFlavor.dev);
    });

    test('lança listando todas as chaves obrigatórias ausentes', () {
      expect(
        () => AppEnv.parse(const {'FLAVOR': 'dev'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('SUPABASE_URL'),
              contains('SUPABASE_ANON_KEY'),
              contains('POWERSYNC_URL'),
            ),
          ),
        ),
      );
    });

    test('trata string vazia/espaços como ausente', () {
      expect(
        () => AppEnv.parse(const {
          'FLAVOR': 'staging',
          'SUPABASE_URL': '   ',
          'SUPABASE_ANON_KEY': 'anon-key-123',
          'POWERSYNC_URL': 'https://x.powersync.journeyapps.com',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toString não expõe a anon key', () {
      final env = AppEnv.parse(valid);
      expect(env.toString(), isNot(contains('anon-key-123')));
      expect(env.toString(), contains('<redacted>'));
    });
  });

  group('AppFlavor', () {
    test('fromName aceita aliases', () {
      expect(AppFlavor.fromName('development'), AppFlavor.dev);
      expect(AppFlavor.fromName('STG'), AppFlavor.staging);
      expect(AppFlavor.fromName('production'), AppFlavor.prod);
    });

    test('fromName rejeita valor inválido', () {
      expect(() => AppFlavor.fromName('qa'), throwsArgumentError);
    });

    test('isProd', () {
      expect(AppFlavor.prod.isProd, isTrue);
      expect(AppFlavor.dev.isProd, isFalse);
    });
  });
}
