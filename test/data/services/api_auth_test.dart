import 'dart:async';

import 'package:biso/data/services/api_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late int created;
  late List<Completer<String>> pending;

  setUp(() {
    now = DateTime.utc(2026, 9, 17, 12);
    created = 0;
    pending = [];
  });

  AppwriteJwtCache counting() =>
      AppwriteJwtCache(() async => 'jwt-${++created}', clock: () => now);

  test('a second call within 10 minutes reuses the token', () async {
    final cache = counting();
    expect(await cache(), 'jwt-1');
    now = now.add(const Duration(minutes: 9, seconds: 59));
    expect(await cache(), 'jwt-1');
    expect(created, 1);
  });

  test('after 10 minutes a new token is created', () async {
    final cache = counting();
    expect(await cache(), 'jwt-1');
    now = now.add(const Duration(minutes: 10));
    expect(await cache(), 'jwt-2');
    expect(created, 2);
  });

  test('concurrent calls share one creation', () async {
    final cache = AppwriteJwtCache(() {
      created++;
      final completer = Completer<String>();
      pending.add(completer);
      return completer.future;
    }, clock: () => now);
    final first = cache();
    final second = cache();
    expect(created, 1);
    pending.single.complete('jwt-shared');
    expect(await first, 'jwt-shared');
    expect(await second, 'jwt-shared');
    expect(await cache(), 'jwt-shared');
    expect(created, 1);
  });

  test('clear forces a new token', () async {
    final cache = counting();
    expect(await cache(), 'jwt-1');
    cache.clear();
    expect(await cache(), 'jwt-2');
  });

  test('a creation that finishes after clear is not cached', () async {
    final cache = AppwriteJwtCache(() {
      created++;
      final completer = Completer<String>();
      pending.add(completer);
      return completer.future;
    }, clock: () => now);
    final stale = cache();
    cache.clear();
    final fresh = cache();
    expect(created, 2);
    pending[0].complete('jwt-old');
    pending[1].complete('jwt-new');
    expect(await stale, 'jwt-old');
    expect(await fresh, 'jwt-new');
    expect(await cache(), 'jwt-new');
    expect(created, 2);
  });

  test('a failure returns null and is not cached', () async {
    var fail = true;
    final cache = AppwriteJwtCache(() async {
      created++;
      if (fail) throw Exception('no session');
      return 'jwt-ok';
    }, clock: () => now);
    expect(await cache(), isNull);
    fail = false;
    expect(await cache(), 'jwt-ok');
    expect(created, 2);
  });
}
