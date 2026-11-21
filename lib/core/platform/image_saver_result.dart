/// What happened to an image the user chose to save.
enum ImageSaveResult {
  /// In the photo library, or downloaded on the web.
  saved,

  /// The user did not allow saving to the photo library.
  denied,

  /// Saving failed for another reason.
  failed,
}
