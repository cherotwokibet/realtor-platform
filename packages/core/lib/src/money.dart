/// Formats whole-shilling amounts the way Kenyan listings show them:
/// "KES 45,000" or, compact, "KES 4.5M".
///
/// Prices are stored as integer shillings. Never use doubles for money.
String formatKes(int amount, {bool compact = false}) {
  if (compact && amount.abs() >= 1000000) {
    return 'KES ${_trim(amount / 1000000)}M';
  }
  if (compact && amount.abs() >= 100000) {
    return 'KES ${_trim(amount / 1000)}K';
  }
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}KES $buf';
}

String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
