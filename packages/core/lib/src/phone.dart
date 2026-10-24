/// Kenyan mobile numbers as people type them ("0712 345 678",
/// "+254-712-345678", "712345678", "0110 123456") -> E.164 "+254712345678".
/// Returns null for anything that is not a Safaricom/Airtel/Telkom mobile
/// (07xx or 01xx). Functions validate the result again (`kenyanPhone`).
String? normaliseKenyanPhone(String input) {
  final digits = input.replaceAll(RegExp(r'[\s\-().]'), '');
  final local = switch (digits) {
    final d when d.startsWith('+254') => d.substring(4),
    final d when d.startsWith('254') && d.length == 12 => d.substring(3),
    final d when d.startsWith('0') => d.substring(1),
    final d => d,
  };
  return RegExp(r'^[17]\d{8}$').hasMatch(local) ? '+254$local' : null;
}
