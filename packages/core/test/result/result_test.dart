import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    const ok = Ok<int, Failure>(42);
    const err = Err<int, Failure>(ValidationFailure('inválido'));

    test('isOk / isErr refletem o caso', () {
      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);
      expect(err.isErr, isTrue);
      expect(err.isOk, isFalse);
    });

    test('valueOrNull e failureOrNull', () {
      expect(ok.valueOrNull, 42);
      expect(ok.failureOrNull, isNull);
      expect(err.valueOrNull, isNull);
      expect(err.failureOrNull, isA<ValidationFailure>());
    });

    test('fold reduz ambos os casos', () {
      expect(ok.fold((v) => 'ok:$v', (f) => 'err'), 'ok:42');
      expect(err.fold((v) => 'ok', (f) => 'err:${f.message}'), 'err:inválido');
    });

    test('map transforma sucesso e preserva falha', () {
      expect(ok.map((v) => v * 2), const Ok<int, Failure>(84));
      expect(err.map((v) => v * 2).failureOrNull, isA<ValidationFailure>());
    });

    test('mapErr transforma falha e preserva sucesso', () {
      final mapped = err.mapErr((f) => NetworkFailure(f.message));
      expect(mapped.failureOrNull, isA<NetworkFailure>());
      expect(ok.mapErr((f) => NetworkFailure(f.message)).valueOrNull, 42);
    });

    test('getOrElse retorna valor ou fallback', () {
      expect(ok.getOrElse((_) => 0), 42);
      expect(err.getOrElse((_) => -1), -1);
    });

    test('igualdade estrutural', () {
      expect(ok, const Ok<int, Failure>(42));
      expect(
        const Err<int, Failure>(ValidationFailure('inválido')),
        const Err<int, Failure>(ValidationFailure('inválido')),
      );
      expect(ok, isNot(const Ok<int, Failure>(1)));
    });

    test('factories nomeadas', () {
      expect(const Result<int, Failure>.ok(1), const Ok<int, Failure>(1));
      expect(
        const Result<int, Failure>.err(UnexpectedFailure('x')),
        const Err<int, Failure>(UnexpectedFailure('x')),
      );
    });
  });

  group('Failure', () {
    test('carrega mensagem, cause e stackTrace', () {
      final st = StackTrace.current;
      final f = DatabaseFailure('falhou', cause: 'boom', stackTrace: st);
      expect(f.message, 'falhou');
      expect(f.cause, 'boom');
      expect(f.stackTrace, st);
      expect(f.toString(), contains('DatabaseFailure'));
    });
  });
}
