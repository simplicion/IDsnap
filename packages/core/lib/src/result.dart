import 'package:docscan_core/src/failure.dart';

/// Outcome of a fallible operation. Engines and repositories never throw
/// across a package boundary; they return a [Result].
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  /// The value, or `null` when this is an [Err].
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  AppFailure? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  R fold<R>(R Function(T value) onOk, R Function(AppFailure failure) onErr) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final failure) => Err(failure),
  };

  Future<Result<R>> then<R>(Future<Result<R>> Function(T value) next) async =>
      switch (this) {
        Ok(:final value) => await next(value),
        Err(:final failure) => Err(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final AppFailure failure;
}

/// Runs [body] and converts any thrown error into an [Err] with [code].
Future<Result<T>> guard<T>(
  Future<T> Function() body, {
  FailureCode code = FailureCode.unknown,
}) async {
  try {
    return Ok(await body());
  } on AppFailure catch (f) {
    return Err(f);
  } on Object catch (e, st) {
    return Err(AppFailure(code, cause: e, stackTrace: st));
  }
}
