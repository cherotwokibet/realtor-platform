import 'package:web/web.dart' as web;

import '../links.dart';

class WebLinkOpener implements LinkOpener {
  @override
  void open(Uri uri) => web.window.open(uri.toString(), '_blank', 'noopener');
}
