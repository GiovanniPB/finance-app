import 'package:meta/meta.dart';

import 'failure.dart';

/// Tipo de retorno para operações que podem falhar de forma recuperável.
///
/// Alternativa a lançar exceptions: o chamador é forçado pelo compilador a
/// tratar ambos os casos via `switch` exaustivo sobre [Ok]/[Err].
///
/// ```dart
/// final result = await repository.load();
/// return switch (result) {
///   Ok(:final value) => value,
///   Err(:final failure) => handle(failure),
/// };
/// ```
@immutable
sealed class Result<S, F extends Failure> {
  const Result();

  /// Cria um resultado de sucesso.
  const factory Result.ok(S value) = Ok<S, F>;

  /// Cria um resultado de falha.
  const factory Result.err(F failure) = Err<S, F>;

  /// `true` se este é um [Ok].
  bool get isOk => this is Ok<S, F>;

  /// `true` se este é um [Err].
  bool get isErr => this is Err<S, F>;

  /// Valor de sucesso, ou `null` se for falha.
  S? get valueOrNull => switch (this) {
    Ok<S, F>(:final value) => value,
    Err<S, F>() => null,
  };

  /// Falha, ou `null` se for sucesso.
  F? get failureOrNull => switch (this) {
    Ok<S, F>() => null,
    Err<S, F>(:final failure) => failure,
  };

  /// Reduz ambos os casos a um único valor de tipo [T].
  T fold<T>(T Function(S value) onOk, T Function(F failure) onErr) =>
      switch (this) {
        Ok<S, F>(:final value) => onOk(value),
        Err<S, F>(:final failure) => onErr(failure),
      };

  /// Transforma o valor de sucesso, preservando a falha.
  Result<T, F> map<T>(T Function(S value) transform) => switch (this) {
    Ok<S, F>(:final value) => Ok<T, F>(transform(value)),
    Err<S, F>(:final failure) => Err<T, F>(failure),
  };

  /// Transforma a falha, preservando o valor de sucesso.
  Result<S, G> mapErr<G extends Failure>(G Function(F failure) transform) =>
      switch (this) {
        Ok<S, F>(:final value) => Ok<S, G>(value),
        Err<S, F>(:final failure) => Err<S, G>(transform(failure)),
      };

  /// Retorna o valor de sucesso ou [fallback] em caso de falha.
  S getOrElse(S Function(F failure) fallback) => switch (this) {
    Ok<S, F>(:final value) => value,
    Err<S, F>(:final failure) => fallback(failure),
  };
}

/// Caso de sucesso de um [Result].
final class Ok<S, F extends Failure> extends Result<S, F> {
  const Ok(this.value);

  final S value;

  @override
  bool operator ==(Object other) => other is Ok<S, F> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

/// Caso de falha de um [Result].
final class Err<S, F extends Failure> extends Result<S, F> {
  const Err(this.failure);

  final F failure;

  @override
  bool operator ==(Object other) =>
      other is Err<S, F> && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Err($failure)';
}
