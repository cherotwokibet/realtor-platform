import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_ui/realtor_ui.dart';

void main() {
  const json = '''{
    "projectId": "demo-project",
    "messagingSenderId": "123",
    "storageBucket": "demo-project.appspot.com",
    "android": {"appId": "1:123:android:a", "apiKey": "ka"},
    "ios": {"appId": "1:123:ios:i", "apiKey": "ki", "bundleId": "ke.example.app"}
  }''';

  test('picks the app for the platform from the generated firebase.json', () {
    final a = parseBundledConfig(json, TargetPlatform.android)!;
    expect((a.appId, a.apiKey, a.projectId, a.messagingSenderId), ('1:123:android:a', 'ka', 'demo-project', '123'));
    final i = parseBundledConfig(json, TargetPlatform.iOS)!;
    expect((i.appId, i.iosBundleId), ('1:123:ios:i', 'ke.example.app'));
  });

  test('no app for the platform, or a broken file, means demo data', () {
    expect(parseBundledConfig('{"projectId":"p","messagingSenderId":"1","android":{"appId":"a","apiKey":"k"}}', TargetPlatform.iOS), isNull);
    expect(parseBundledConfig('nope', TargetPlatform.android), isNull);
  });
}
