import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Widest the content gets on tablets and desktop web; centred beyond it.
const maxContentWidth = 1200.0;

/// Back on every screen below the tabs: to the screen before, or Home when
/// the screen was opened straight from a link and there is nothing behind it.
class AppBack extends StatelessWidget {
  const AppBack({super.key});

  @override
  Widget build(BuildContext context) => BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/'));
}
