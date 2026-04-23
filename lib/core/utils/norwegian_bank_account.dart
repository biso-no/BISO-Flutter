String normalizeNorwegianBankAccount(String value) {
  return value.replaceAll(RegExp(r'[^\d]'), '');
}

bool isValidNorwegianBankAccount(String accountNumber) {
  final normalized = normalizeNorwegianBankAccount(accountNumber);
  if (normalized.length != 11 || !RegExp(r'^\d{11}$').hasMatch(normalized)) {
    return false;
  }

  const weights = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  var sum = 0;
  for (var i = 0; i < weights.length; i++) {
    sum += int.parse(normalized[i]) * weights[i];
  }

  final remainder = sum % 11;
  final checkDigit = remainder == 0 ? 0 : 11 - remainder;

  if (checkDigit == 10) {
    return false;
  }

  return checkDigit == int.parse(normalized[10]);
}

String formatNorwegianBankAccount(String accountNumber) {
  final normalized = normalizeNorwegianBankAccount(accountNumber);
  if (normalized.length != 11) {
    return accountNumber;
  }

  return '${normalized.substring(0, 4)} ${normalized.substring(4, 6)} ${normalized.substring(6)}';
}

String? validateNorwegianBankAccount(String? value, {bool required = true}) {
  if (value == null || value.isEmpty) {
    return required ? 'Bank account number is required' : null;
  }

  final normalized = normalizeNorwegianBankAccount(value);
  if (normalized.length != 11) {
    return 'Norwegian bank account must be 11 digits';
  }

  if (!isValidNorwegianBankAccount(normalized)) {
    return 'Invalid Norwegian bank account number';
  }

  return null;
}
