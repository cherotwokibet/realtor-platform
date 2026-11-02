import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../listing_media.dart';

/// The browser's file chooser, several files at once.
class WebFilePicker implements FilePicker {
  @override
  Future<List<PickedFile>> pick({required String accept}) {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = true
      ..accept = accept;
    // In the page (hidden) while picking: some browsers ignore a detached input.
    input.style.display = 'none';
    web.document.body!.append(input);
    final done = Completer<List<PickedFile>>();
    void changed(web.Event _) => unawaited(_read(input.files).then((files) {
          if (!done.isCompleted) done.complete(files);
        }, onError: (Object e, StackTrace st) {
          if (!done.isCompleted) done.completeError(e, st);
        }));
    input.addEventListener('change', changed.toJS);
    void cancelled(web.Event _) {
      if (!done.isCompleted) done.complete(const []);
    }

    input.addEventListener('cancel', cancelled.toJS);
    input.click();
    return done.future.whenComplete(() => input.remove());
  }

  static Future<List<PickedFile>> _read(web.FileList? files) async {
    final out = <PickedFile>[];
    for (var i = 0; i < (files?.length ?? 0); i++) {
      final f = files!.item(i)!;
      final buffer = await f.arrayBuffer().toDart;
      out.add((name: f.name, bytes: buffer.toDart.asUint8List(), type: f.type));
    }
    return out;
  }
}
