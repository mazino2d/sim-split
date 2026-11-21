import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:simsplit/core/platform/image_saver_result.dart';

export 'package:simsplit/core/platform/image_saver_result.dart';

/// Downloads PNG images through the browser, one file each.
Future<ImageSaveResult> saveImages(
    List<({String name, Uint8List bytes})> images) async {
  try {
    for (final image in images) {
      final blob = web.Blob(
          [image.bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
      final url = web.URL.createObjectURL(blob);
      final link = web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = image.name
        ..style.display = 'none';
      web.document.body!.append(link);
      link.click();
      link.remove();
      // Give the browser time to start the download before freeing it.
      Future<void>.delayed(
          const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
      // Browsers may drop downloads started in the same instant.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return ImageSaveResult.saved;
  } on Object {
    return ImageSaveResult.failed;
  }
}

/// Nothing to open on the web: the file is in the browser's downloads.
Future<void> openSavedImages() async {}
