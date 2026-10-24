/// Design tokens derived from a tenant config. Pure Dart: used by the
/// Flutter theme (packages/ui) and by the Jaspr share pages (as CSS).
library;

import 'package:realtor_core/realtor_core.dart';

/// Spacing steps on the tenant's base grid (4 or 8 px).
class Spacing {
  const Spacing(this.base);
  final double base;
  double get xs => base; // 4
  double get sm => base * 2; // 8
  double get md => base * 3; // 12
  double get lg => base * 4; // 16
  double get xl => base * 6; // 24
  double get xxl => base * 8; // 32

  /// Phone side gutter.
  double get gutter => lg;
}

class Tokens {
  Tokens(this.tenant) : spacing = Spacing(tenant.brand.spacingBase);
  final TenantConfig tenant;
  final Spacing spacing;

  BrandColors get colors => tenant.brand.colors;
  TypeScale get type => tenant.brand.typeScale;

  /// CSS custom properties. Same names and order as tools/tenant-cli/src/css.ts.
  String toCss() {
    final c = colors;
    final colorMap = <String, int>{
      'primary': c.primary,
      'onPrimary': c.onPrimary,
      'primarySoft': c.primarySoft,
      'accent': c.accent,
      'onAccent': c.onAccent,
      'accentText': c.accentText,
      'ink': c.ink,
      'text': c.text,
      'textMuted': c.textMuted,
      'border': c.border,
      'borderStrong': c.borderStrong,
      'surface': c.surface,
      'background': c.background,
      'surfaceAlt': c.surfaceAlt,
      'info': c.info,
      'success': c.success,
      'error': c.error,
    };
    final t = type;
    final typeMap = <String, double>{
      'caption': t.caption,
      'body': t.body,
      'bodyLarge': t.bodyLarge,
      'title': t.title,
      'headline': t.headline,
      'display': t.display,
    };
    final b = tenant.brand;
    final lines = <String>[
      for (final e in colorMap.entries) '  --color-${_kebab(e.key)}: ${hex(e.value)};',
      for (final e in typeMap.entries) '  --text-${_kebab(e.key)}: ${_num(e.value / 16)}rem;',
      '  --radius-sm: ${_num(b.radiusSm)}px;',
      '  --radius-md: ${_num(b.radiusMd)}px;',
      '  --radius-pill: ${_num(b.radiusPill)}px;',
      '  --space: ${_num(b.spacingBase)}px;',
      '  --font-display: "${b.displayFont}", system-ui, sans-serif;',
      '  --font-body: "${b.bodyFont}", system-ui, sans-serif;',
    ];
    return '/* Generated from tenants/${tenant.id}.json. Do not edit. */\n:root {\n${lines.join('\n')}\n}\n';
  }
}

/// 0xFF5E0202 -> "#5E0202".
String hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _kebab(String s) => s.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

/// Matches JavaScript number printing for the values we use (12 -> "12", 0.875 -> "0.875").
String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
