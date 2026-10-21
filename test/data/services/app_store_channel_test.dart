import 'dart:async';

import 'package:biso/data/services/app_store_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('biso/app_store');
  late List<MethodCall> calls;

  void handle(Future<Object?>? Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          handler == null
              ? null
              : (call) {
                  calls.add(call);
                  return handler(call);
                },
        );
  }

  setUp(() => calls = []);
  tearDown(() => handle(null));

  test('talks to biso/app_store by default', () async {
    handle((call) async => null);

    await const AppStoreChannel().showProductPage('6468173379');

    expect(calls, hasLength(1));
  });

  test('asks for the product page of the given item', () async {
    handle((call) async => null);

    await const AppStoreChannel().showProductPage('6468173379');

    expect(calls.single.method, 'showProductPage');
    expect(calls.single.arguments, {'itemId': '6468173379'});
  });

  test('completes only once the sheet is dismissed', () async {
    final dismissed = Completer<Object?>();
    handle((call) => dismissed.future);

    var done = false;
    final shown = const AppStoreChannel()
        .showProductPage('6468173379')
        .then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);

    dismissed.complete(null);
    await shown;
    expect(done, isTrue);
  });

  for (final code in ['load_failed', 'no_presenter', 'busy']) {
    test('passes on the native $code error', () async {
      handle((call) async => throw PlatformException(code: code));

      await expectLater(
        const AppStoreChannel().showProductPage('6468173379'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    });
  }

  test('throws MissingPluginException without the native channel', () async {
    await expectLater(
      const AppStoreChannel().showProductPage('6468173379'),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
