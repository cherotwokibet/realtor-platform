import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/sections.dart';
import 'package:realtor_core/realtor_core.dart';

void main() {
  Features only(Set<Feature> on) => Features.fromJson({for (final f in Feature.values) f.name: on.contains(f)});

  test('disabled sections and their sub-paths redirect home', () {
    final f = only({Feature.rent});
    expect(redirectForDisabled(f, '/chat'), '/');
    expect(redirectForDisabled(f, '/off-plan/riverside-heights'), '/');
    expect(redirectForDisabled(f, '/chatter'), isNull, reason: 'prefix must be a whole segment');
    expect(redirectForDisabled(f, '/saved'), isNull);
    expect(redirectForDisabled(f, '/listing/2br-kilimani'), isNull);
  });

  test('menu follows the switches', () {
    expect(enabledSections(only({})).map((s) => s.path), ['/', '/saved', '/account']);
    expect(enabledSections(only(Feature.values.toSet())).length, appSections.length);
  });
}
