import 'package:flutter/material.dart';
import 'package:realtor_core/realtor_core.dart';

import 'search/purpose.dart';

/// A top-level part of the app: one route and one navigation destination.
/// Sections with a [feature] exist only when the tenant has it on: no route,
/// no menu entry, and deep links to them go home.
class AppSection {
  const AppSection(this.path, this.label, this.icon, {this.feature, this.signedInOnly = false});
  final String path, label;
  final IconData icon;
  final Feature? feature;

  /// Shown in the navigation only to a signed-in customer (Saved).
  final bool signedInOnly;

  bool enabledFor(Features f) => feature == null || f.isOn(feature!);
}

const appSections = [
  AppSection('/', 'Search', Icons.search),
  AppSection('/off-plan', 'Off-plan', Icons.apartment_outlined, feature: Feature.offPlan),
  AppSection('/saved', 'Saved', Icons.favorite_border, signedInOnly: true),
  AppSection('/chat', 'Chat', Icons.chat_bubble_outline, feature: Feature.chat),
  AppSection('/account', 'Account', Icons.person_outline),
];

List<AppSection> enabledSections(Features f) => [for (final s in appSections) if (s.enabledFor(f)) s];

/// Where a location should go instead, or null if it may open as is.
String? redirectForDisabled(Features f, String location) {
  final first = location.split('/').where((s) => s.isNotEmpty).firstOrNull;
  final purpose = first == null ? null : Purpose.fromPath(first);
  if (purpose != null && !f.isOn(purpose.feature)) return '/';
  for (final s in appSections) {
    if (s.path == '/' || s.enabledFor(f)) continue;
    if (location == s.path || location.startsWith('${s.path}/')) return '/';
  }
  return null;
}

/// The sections the navigation shows: Saved only once someone has signed in.
List<AppSection> visibleSections(List<AppSection> enabled, {required bool signedIn}) =>
    [for (final s in enabled) if (signedIn || !s.signedInOnly) s];
