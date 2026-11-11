/// The retry policy for every provider in the app: none.
///
/// Riverpod 3 retries a failing provider on its own and reports it as loading
/// until the retries run out, so a screen watching it never sees the error.
/// Screens here show a failure with their own "Try again" instead, and the
/// providers that should ask again (on resume, on reconnect) already do. Set
/// on the root `ProviderScope`; nested scopes and containers inherit it.
Duration? noAutomaticRetry(int retryCount, Object error) => null;
