/// Formats a NOK amount the way the shop shows prices.
///
/// Prices in the webshop are almost always whole kroner, and "NOK 249.00"
/// reads worse than "NOK 249" for those — but a member discount is a
/// percentage, so it can land on øre and those must not be silently rounded
/// away from a total the buyer is about to be charged. Decimals therefore
/// appear only when the amount actually has them.
String formatNok(num amount) {
  final rounded = (amount * 100).round() / 100;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(2);
  return 'NOK $text';
}
