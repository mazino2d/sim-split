import 'dart:typed_data';

import 'package:gal/gal.dart';

import 'package:simsplit/core/platform/image_saver_result.dart';

export 'package:simsplit/core/platform/image_saver_result.dart';

/// Saves PNG images to the photo library, in the "SimSplit" album. Asks for
/// permission first where the system needs it.
Future<ImageSaveResult> saveImages(
    List<({String name, Uint8List bytes})> images) async {
  try {
    if (!await Gal.hasPermission(toAlbum: true) &&
        !await Gal.requestPermission(toAlbum: true)) {
      return ImageSaveResult.denied;
    }
    for (final image in images) {
      await Gal.putImageBytes(image.bytes,
          album: 'SimSplit', name: image.name.replaceAll('.png', ''));
    }
    return ImageSaveResult.saved;
  } on GalException catch (e) {
    return e.type == GalExceptionType.permissionDenied
        ? ImageSaveResult.denied
        : ImageSaveResult.failed;
  } on Object {
    return ImageSaveResult.failed;
  }
}

/// Opens the photo library, to see what was saved.
Future<void> openSavedImages() async {
  try {
    await Gal.open();
  } on Object {
    // Nothing to open on this device.
  }
}
