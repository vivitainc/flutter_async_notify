import 'dart:async';

import 'package:async_notify/async_notify.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notify', () async {
    final notify = Notify();
    try {
      unawaited(() async {
        await Future<void>.delayed(const Duration(seconds: 1));
        debugPrint('notify');
        notify.notify();
        debugPrint('notify.done!');
      }());
      debugPrint('wait...');
      await notify.wait(); // wait 1sec.
      debugPrint('wait.done!');
    } finally {
      await notify.dispose();
    }
  });
}
