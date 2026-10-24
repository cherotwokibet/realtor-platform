import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

/// Overridden in main() with the tenant loaded from assets.
final tenantProvider = Provider<TenantConfig>((ref) => throw UnimplementedError('tenantProvider not overridden'));
