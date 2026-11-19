import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Widest the content gets on tablets and desktop web; centred beyond it.
const maxContentWidth = 1200.0;

/// Results pages: the homes and the column beside them, as wide as on the
/// big portals (a list about 775 wide, a 300 column, a 25 gap), plus gutters.
const resultsContentWidth = 1100.0 + 2 * 24;

/// From this width (Material 3 "expanded") the app has a top navigation
/// bar and no bottom bar.
const wideLayoutFrom = 840.0;

/// Where the visitor has been in this visit, so back returns to the page
/// they came from even when it was reached by a tab or a menu (which replace
/// the page rather than stack it). Kept per router.
class NavHistory {
  NavHistory._();
  static final _byRouter = Expando<NavHistory>();

  /// The history of [router], made on first use.
  static NavHistory of(GoRouter router) => _byRouter[router] ??= NavHistory._();

  final _stack = <String>[];
  bool _goingBack = false;

  /// Called on every change of page.
  void visit(String location) {
    if (_goingBack) {
      _goingBack = false;
      return;
    }
    if (_stack.isNotEmpty && _stack.last == location) return;
    _stack.add(location);
    if (_stack.length > 50) _stack.removeAt(0);
  }

  /// The page before this one (forgetting this one), or null at the start.
  String? back() {
    if (_stack.length < 2) return null;
    _stack.removeLast();
    _goingBack = true;
    return _stack.last;
  }
}

/// Back, from wherever: the screen stacked under this one, else the page
/// visited before it, else Home (opened straight from a link).
void goBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  final router = GoRouter.of(context);
  router.go(NavHistory.of(router).back() ?? '/');
}

/// Back on every screen below the tabs (see [goBack]).
class AppBack extends StatelessWidget {
  const AppBack({super.key});

  @override
  Widget build(BuildContext context) => BackButton(onPressed: () => goBack(context));
}
