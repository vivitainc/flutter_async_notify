/// 非同期処理のキャンセル時に投げられる例外.
class CancellationException implements Exception {
  final String message;

  CancellationException(this.message);

  @override
  String toString() {
    // ignore: no_runtimetype_tostring
    return '$runtimeType{message: $message}';
  }
}
