import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../reports.dart';

/// Saves through a temporary download link.
class WebFileSaver implements FileSaver {
  @override
  void save(String fileName, String text, {String type = 'text/csv'}) {
    final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: '$type;charset=utf-8'));
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body!.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
  }
}
