import 'cancellation_exception.dart';

/// 非同期処理のタイムアウト時に投げられる.
class TimeoutCancellationException extends CancellationException {
  final Duration duration;
  TimeoutCancellationException(String message, this.duration) : super(message);
}
