import 'package:equatable/equatable.dart';

/// A payment provider the shop can offer.
enum PaymentProvider {
  vipps('vipps'),
  stripe('stripe');

  const PaymentProvider(this.id);

  final String id;

  static PaymentProvider? fromId(String? value) {
    for (final provider in PaymentProvider.values) {
      if (provider.id == value) return provider;
    }
    return null;
  }

  /// What the buyer sees on the picker.
  String get displayName => switch (this) {
    PaymentProvider.vipps => 'Vipps',
    PaymentProvider.stripe => 'Card',
  };

  String get description => switch (this) {
    PaymentProvider.vipps => 'Pay with Vipps MobilePay',
    PaymentProvider.stripe => 'Pay by card',
  };
}

/// Whether a provider may be offered right now, as the server sees it.
///
/// Two independent switches gate a provider and both live server-side: the
/// `payments_vipps` / `payments_stripe` kill switch administrators toggle in
/// the admin app, and whether that provider's credentials are configured. The
/// second cannot be read from the app at all — `payment_settings` is not
/// readable by end users — so the app asks `GET /api/payment/providers` rather
/// than trying to work it out. Offering a provider the server would refuse
/// means sending the buyer to a dead end.
class PaymentProviderAvailability extends Equatable {
  final PaymentProvider provider;

  /// Offerable: both switched on and configured.
  final bool available;

  /// The admin app's kill switch.
  final bool enabled;

  /// Whether the active-mode credentials are present.
  final bool configured;

  const PaymentProviderAvailability({
    required this.provider,
    required this.available,
    required this.enabled,
    required this.configured,
  });

  static PaymentProviderAvailability? fromJson(Map<String, dynamic> json) {
    final provider = PaymentProvider.fromId(json['id']?.toString());
    if (provider == null) return null;
    return PaymentProviderAvailability(
      provider: provider,
      available: json['available'] == true,
      enabled: json['enabled'] == true,
      configured: json['configured'] == true,
    );
  }

  @override
  List<Object?> get props => [provider, available, enabled, configured];
}
