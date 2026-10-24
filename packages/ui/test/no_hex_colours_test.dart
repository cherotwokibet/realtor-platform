import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Colours come from the tenant file through buildBrandTheme. Widgets read
/// the theme; a literal colour in UI code would not follow a re-brand.
void main() {
  final banned = <String, RegExp>{
    'Color(0x…) literal': RegExp(r'Color\(\s*0x[0-9A-Fa-f]+'),
    'Color.fromARGB/fromRGBO': RegExp(r'Color\.from(ARGB|RGBO)\('),
    '#RRGGBB string': RegExp(r'''['"]#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?['"]'''),
    'Material Colors.* palette': RegExp(r'\bColors\.(?!transparent\b)\w+'),
  };

  for (final dir in ['lib', '../../apps/realtor_app/lib']) {
    test('no hard-coded colours in $dir', () {
      final problems = <String>[];
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          for (final MapEntry(key: what, value: re) in banned.entries) {
            if (re.hasMatch(line)) problems.add('${f.path}:${i + 1}: $what');
          }
        }
      }
      expect(problems, isEmpty, reason: 'Use Theme.of(context) / context.brand instead.');
    });
  }
}
