import 'package:flutter/services.dart';

enum WalletAddResult { added, cancelled }

/// Apple Wallet through `biso/wallet` in `AppDelegate.swift`. The pass
/// bytes go straight to PassKit and never touch disk.
class WalletChannel {
  const WalletChannel([this._channel = const MethodChannel('biso/wallet')]);

  final MethodChannel _channel;

  Future<bool> canAddPasses() async {
    try {
      return await _channel.invokeMethod<bool>('canAddPasses') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Presents Apple's add-pass sheet. Throws a [PlatformException] with code
  /// `invalid_pass` when PassKit cannot read [bytes], `cannot_add` when this
  /// device cannot add passes, `no_presenter` when the sheet could not be
  /// shown, and `busy` while another sheet is on screen.
  Future<WalletAddResult> addPass(Uint8List bytes) async {
    final result = await _channel.invokeMethod<String>('addPass', {
      'pass': bytes,
    });
    return result == 'added'
        ? WalletAddResult.added
        : WalletAddResult.cancelled;
  }
}
