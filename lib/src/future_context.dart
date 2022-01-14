import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:tuple/tuple.dart';

import 'cancellation_exception.dart';
import 'notify.dart';
import 'notify_channel.dart';
import 'timeout_cancellation_exception.dart';

/// 非同期処理のキャンセル不可能な1ブロック処理
/// このブロック完了後、FutureContextは復帰チェックを行い、必要であればキャンセル等を行う.
typedef FutureSuspendBlock<T> = Future<T> Function(FutureContext context);

/// 非同期（Async）状態を管理する.
/// FutureContextの目標はキャンセル可能な非同期処理のサポートである.
///
/// 処理終了後、必ず [dispose] をコールする必要がある.
///
/// 開発者はFutureContext.suspend()に関数を渡し、実行を行う.
/// suspend()は実行前後にFutureContextの状態を確認し、必要であればキャンセル等の処理や中断を行う.
///
/// NOTE. 2021-05
/// Flutter 2.2(Dart 2.12)現在、言語仕様としてKotlinのSuspend関数のような状態管理を行えない.
/// そのため、開発者側で適度にブロックを区切って実行を行えるようサポートする.
///
/// KotlinにはCoroutineDispatcherのようなさらに上位（周辺）の仕組みがあるが、
/// 目的に対してオーバースペックであるため実装を見送る.
///
/// 処理が冗長になることと、Dart標準からかけ離れていくリスクがあるため、
/// 使用箇所については慎重に検討が必要.
class FutureContext {
  /// 親Context.
  final FutureContext? _parent;

  final _notify = Notify();

  /// 発生済みエラー
  Exception? _error;

  /// 処理が完了している場合true.
  // ignore: prefer_final_fields
  bool _done = false;

  factory FutureContext() => FutureContext._launch(
        parent: null,
      );

  FutureContext._launch({FutureContext? parent}) : _parent = parent;

  /// 処理が継続中の場合trueを返却する.
  bool get isActive => !_done && _error == null && !_notify.isClosed;

  /// 処理がキャンセル済みの場合true.
  bool get isCanceled => _error is CancellationException;

  /// Futureをキャンセルする.
  /// すでにキャンセル済みの場合は何もしない.
  void cancel(String message) {
    _cancel(CancellationException(message));
  }

  /// 指定時間Contextを停止させる.
  /// delayed()の最中にキャンセルが発生した場合、速やかにContext処理は停止する.
  ///
  /// e.g.
  /// context.delayed(Duration(seconds: 1));
  Future delayed(final Duration duration) async {
    _resume();
    await _notify.delay(duration);
    _resume();
  }

  void dispose() {
    _notify.dispose();
    cancel('FutureContext.dispose()');
  }

  /// このFutureContextに紐付いたChannelオブジェクトを生成する.
  /// このFutureContextが [cancel] されたとき、自動的にChannelもキャンセル扱いとなる.
  NotifyChannel<T> makeChannel<T>() => NotifyChannel(_notify);

  /// 非同期処理の特定1ブロックを実行する.
  /// これはFutureContext<T>の実行最小単位として機能する.
  /// suspend内部では実行開始時・終了時にそれぞれAsyncContextのステートチェックを行い、
  /// 必要であれば例外を投げる等の中断処理を行う.
  ///
  /// 開発者は可能な限り細切れに suspend() に処理を分割することで、
  /// 処理の速やかな中断のサポートを受けることができる.
  Future<T2> suspend<T2>(FutureSuspendBlock<T2> block) async {
    _resume();
    final channel = NotifyChannel<Tuple2<T2?, Exception?>>(_notify);
    unawaited(() async {
      try {
        final value = await block(this);
        if (!channel.isClosed) {
          channel.send(Tuple2(value, null));
        }
      } on Exception catch (e) {
        if (!channel.isClosed) {
          channel.send(Tuple2(null, e));
        }
      }
    }());
    try {
      final pair = await channel.receive();
      if (pair.item2 != null) {
        throw pair.item2!;
      }
      _resume();
      return pair.item1 as T2;
    } on Exception catch (_) {
      if (_error != null) {
        throw _error!;
      } else {
        rethrow;
      }
    }
  }

  /// タイムアウト付きの非同期処理を開始する.
  ///
  /// タイムアウトが発生した場合、
  /// block()は [TimeoutCancellationException] が発生して終了する.
  Future<T2> withTimeout<T2>(
      Duration timeout, FutureSuspendBlock<T2> block) async {
    final child = FutureContext._launch(parent: this);
    try {
      unawaited(() async {
        try {
          await child.suspend((context) async {
            await context.delayed(timeout);
            if (child.isActive) {
              // 指定時間経ってもタスクが終わっていないので、タイムアウト扱いにする.
              child._cancel(
                TimeoutCancellationException(
                  'withContext<$T2>.timeout',
                  timeout,
                ),
              );
            }
          });
        } on CancellationException catch (_) {
          // ChildContextのキャンセル処理はdropする.
        }
      }());
      return await child.suspend(block);
    } finally {
      child.dispose();
    }
  }

  /// [Stream] の有効期限をこのインスタンスに合わせる.
  /// Listen側が終了するか、このFutureContextが閉じられると転送を終了する.
  Stream<T2> wrapStream<T2>(Stream<T2> stream) {
    final subject = PublishSubject<T2>();

    // 入れ違いを防ぐため、最初にStreamを作る
    final result = () async* {
      await for (final v in subject.stream) {
        yield v;
      }
    }();

    // stream -> channel -> subjectでデータを流す
    // FutureContextの寿命よりも早くStreamが終了した場合、Subjectを閉じて強制終了させる.
    final channel = makeChannel<T2>();
    final subscription = stream.listen((event) => channel.send(event));
    subscription.onDone(() => subject.close());

    unawaited(() async {
      try {
        while (isActive) {
          try {
            subject.add(await channel.receive());
          } on CancellationException catch (_) {
            return;
          }
        }
      } finally {
        if (!subject.isClosed) {
          unawaited(subject.close());
        }
        unawaited(subscription.cancel());
      }
    }());
    return result;
  }

  void _cancel(CancellationException e) {
    if (isCanceled) {
      return;
    }
    assert(_error == null, 'FutureContext invalid state');
    _error = e;
    // 1サイクル遅れてDisposeを実行する.
    () async {
      dispose();
    }();
  }

  // /// 子Jobを作成する.
  // /// 親がキャンセルされると、子は自動的にキャンセルされる.
  // Job<T2> launch<T2>(LaunchFunction<T2> block) {
  //   _resume();
  //   final context = FutureContext._launch(parent: this);
  //   return Job<T2>._init(context, block);
  // }

  /// 非同期処理の状態をチェックし、必要であれはキャンセル処理を発生させる.
  void _resume() {
    _parent?._resume(); // 親のResumeチェック

    // 自分自身のResume Check.
    if (_error != null) {
      throw _error!;
    }
  }

  /// 制御に紐付かないFutureContextを生成する.
  /// 子Jobの統括などの利用を想定する.
  @Deprecated('replace to FutureContext()')
  static FutureContext empty() {
    return FutureContext._launch();
  }
}
