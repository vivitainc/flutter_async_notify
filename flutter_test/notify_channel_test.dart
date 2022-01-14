import 'package:async_plus/async_plus.dart';
import 'package:flutter_test/flutter_test.dart';

Future main() async {
  test('NotifyChannel.receive()', () async {
    final channel = NotifyChannel<int>(Notify());

    channel.send(0);
    channel.send(1);

    expect(channel.isNotEmpty, isTrue);
    expect(await channel.receive(), equals(0));
    expect(await channel.receive(), equals(1));
    expect(channel.isEmpty, isTrue);
  });
}
