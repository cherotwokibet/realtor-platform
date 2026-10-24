import 'package:realtor_core/realtor_core.dart';

/// App wording and feature switch for each search purpose.
extension PurposeUi on Purpose {
  String get label => switch (this) { Purpose.rent => 'Rent', Purpose.sale => 'Buy', Purpose.shortStay => 'Short stay' };
  String get heading => switch (this) { Purpose.rent => 'to rent', Purpose.sale => 'for sale', Purpose.shortStay => 'for short stays' };
  Feature get feature => switch (this) { Purpose.rent => Feature.rent, Purpose.sale => Feature.sale, Purpose.shortStay => Feature.shortStay };

  /// Price period shown after a price.
  String? get period => switch (this) { Purpose.rent => 'month', Purpose.sale => null, Purpose.shortStay => 'night' };
}

/// "south-b" -> "South B", "single-room" -> "Single room".
String areaName(String slug) => slug.split('-').map((w) => w.length <= 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
String typeName(String type) {
  final s = type.replaceAll('-', ' ');
  return '${s[0].toUpperCase()}${s.substring(1)}';
}
