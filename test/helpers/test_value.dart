import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A value a test sets by hand, as `container.read(p.notifier).state = x`.
///
/// What a legacy `StateProvider` used to be for in these tests.
class TestValue<T> extends Notifier<T> {
  TestValue(this._initial);

  final T _initial;

  @override
  T build() => _initial;
}

/// A provider holding [initial] until a test sets something else.
NotifierProvider<TestValue<T>, T> testValueProvider<T>(T initial) =>
    NotifierProvider<TestValue<T>, T>(() => TestValue<T>(initial));
