import 'package:flutter/material.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_tokens/realtor_tokens.dart';
import 'tenant_scope.dart';

/// Brand colours Material's ColorScheme has no slot for.
/// Read with `context.brand`.
@immutable
class BrandExtension extends ThemeExtension<BrandExtension> {
  const BrandExtension({
    required this.primarySoft,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.textMuted,
    required this.borderStrong,
    required this.surfaceAlt,
    required this.info,
    required this.success,
    required this.radiusSm,
    required this.radiusMd,
    required this.spacing,
    required this.logoAsset,
  });

  final Color primarySoft, accent, onAccent, accentText, textMuted, borderStrong;
  final Color surfaceAlt, info, success;
  final double radiusSm, radiusMd;
  final Spacing spacing;
  final String logoAsset;

  @override
  BrandExtension copyWith() => this;

  @override
  BrandExtension lerp(BrandExtension? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BrandExtension(
      primarySoft: l(primarySoft, other.primarySoft),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentText: l(accentText, other.accentText),
      textMuted: l(textMuted, other.textMuted),
      borderStrong: l(borderStrong, other.borderStrong),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      info: l(info, other.info),
      success: l(success, other.success),
      radiusSm: radiusSm,
      radiusMd: radiusMd,
      spacing: spacing,
      logoAsset: t < 0.5 ? logoAsset : other.logoAsset,
    );
  }
}

extension BrandContext on BuildContext {
  BrandExtension get brand => Theme.of(this).extension<BrandExtension>()!;
}

/// Builds the app/admin theme from a tenant. The only place colours enter Flutter.
ThemeData buildBrandTheme(TenantConfig tenant) {
  final tokens = Tokens(tenant);
  final c = tokens.colors;
  final ts = tokens.type;
  final b = tenant.brand;

  final scheme = ColorScheme.light(
    primary: Color(c.primary),
    onPrimary: Color(c.onPrimary),
    primaryContainer: Color(c.primarySoft),
    onPrimaryContainer: Color(c.primary),
    secondary: Color(c.accent),
    onSecondary: Color(c.onAccent),
    // Selected chips/segments use the soft primary tint, not the accent.
    secondaryContainer: Color(c.primarySoft),
    onSecondaryContainer: Color(c.primary),
    surface: Color(c.surface),
    onSurface: Color(c.ink),
    onSurfaceVariant: Color(c.textMuted),
    surfaceContainerLowest: Color(c.background),
    surfaceContainerHighest: Color(c.surfaceAlt),
    outline: Color(c.borderStrong),
    outlineVariant: Color(c.border),
    error: Color(c.error),
    onError: Color(c.onPrimary),
  );

  TextStyle s(double size, FontWeight w, {String? font, int? color}) => TextStyle(
        fontFamily: font ?? b.bodyFont,
        fontSize: size,
        fontWeight: w,
        color: Color(color ?? c.text),
        height: 1.4,
      );

  final text = TextTheme(
    displaySmall: s(ts.display, FontWeight.w700, font: b.displayFont, color: c.ink),
    headlineMedium: s(ts.headline, FontWeight.w600, font: b.displayFont, color: c.ink),
    titleLarge: s(ts.title, FontWeight.w600, font: b.displayFont, color: c.ink),
    titleMedium: s(ts.bodyLarge, FontWeight.w600, color: c.ink),
    bodyLarge: s(ts.bodyLarge, FontWeight.w400),
    bodyMedium: s(ts.body, FontWeight.w400),
    labelLarge: s(ts.body, FontWeight.w600, color: c.ink),
    bodySmall: s(ts.caption, FontWeight.w400, color: c.textMuted),
    labelSmall: s(ts.caption, FontWeight.w500, color: c.textMuted),
  );

  final md = BorderRadius.circular(b.radiusMd);
  final sm = BorderRadius.circular(b.radiusSm);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Color(c.background),
    fontFamily: b.bodyFont,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Color(c.surface),
      foregroundColor: Color(c.ink),
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: text.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: sm),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: sm),
        side: BorderSide(color: Color(c.borderStrong)),
        foregroundColor: Color(c.ink),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(c.surface),
      border: OutlineInputBorder(borderRadius: sm, borderSide: BorderSide(color: Color(c.border))),
      enabledBorder: OutlineInputBorder(borderRadius: sm, borderSide: BorderSide(color: Color(c.border))),
      focusedBorder: OutlineInputBorder(borderRadius: sm, borderSide: BorderSide(color: Color(c.primary), width: 1.5)),
      hintStyle: text.bodyMedium?.copyWith(color: Color(c.textMuted)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusPill)),
      side: BorderSide(color: Color(c.borderStrong)),
      selectedColor: Color(c.primarySoft),
      labelStyle: text.bodyMedium,
    ),
    cardTheme: CardThemeData(
      color: Color(c.surface),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: md, side: BorderSide(color: Color(c.border))),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: Color(c.border), space: 1),
    extensions: [
      BrandExtension(
        primarySoft: Color(c.primarySoft),
        accent: Color(c.accent),
        onAccent: Color(c.onAccent),
        accentText: Color(c.accentText),
        textMuted: Color(c.textMuted),
        borderStrong: Color(c.borderStrong),
        surfaceAlt: Color(c.surfaceAlt),
        info: Color(c.info),
        success: Color(c.success),
        radiusSm: b.radiusSm,
        radiusMd: b.radiusMd,
        spacing: tokens.spacing,
        // Flavor builds keep each tenant's files in their own folder.
        logoAsset: '${tenantAssetDir()}/logo-horizontal.png',
      ),
    ],
  );
}
