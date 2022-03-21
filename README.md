async_notify

| CI / CD | ビルドステータス |
|---|---|
| Github Actions | [![Github Actions](https://github.com/vivitainc/flutter_async_notify/actions/workflows/flutter-package-test.yaml/badge.svg)](https://github.com/vivitainc/flutter_async_notify/actions/workflows/flutter-package-test.yaml) |

## Features

Notify(wait-notify) support Library.

* Notify
    Message(Object)の非同期待ち合わせ.
* NotifyChannel
    非同期の値送信/待ち合わせ.

## Usage


```dart
// Notify
final notify = Notify();
await notify.wait(); // wait Notify.notify() call.

// finalize.
notify.dispose();
```

```dart
// NotifyChannel.

final notify = Notify();
final channel = NotifyChannel<int>(notify);

await channel.receive();    // wait NotifyChannel.send(value);

// finalize.
notify.dispose();
```

## Additional information
