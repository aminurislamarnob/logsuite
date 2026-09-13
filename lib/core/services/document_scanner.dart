import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

final documentScannerProvider = Provider<DocumentScanner>(
  (ref) => DocumentScanner(),
);

/// Gets a receipt, bill or note from the camera or the gallery, framed.
///
/// A receipt photographed on a table brings the table with it, and the OCR
/// step reads every word it can see, so the cropper runs after every pick:
/// one tap confirms the full frame, a drag trims it. Cancelling the crop
/// abandons the scan rather than sending the uncropped photo, since the
/// crop screen is the last thing the user sees before the text leaves for
/// the model.
class DocumentScanner {
  DocumentScanner({ImagePicker? picker, ImageCropper? cropper})
    : _picker = picker ?? ImagePicker(),
      _cropper = cropper ?? ImageCropper();

  final ImagePicker _picker;
  final ImageCropper _cropper;

  Future<File?> pick({required bool fromCamera}) async {
    XFile? photo;
    try {
      photo = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        // A ceiling on what gets decoded; ML Kit needs no more than this.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
    } on Exception catch (e) {
      debugPrint('Document pick failed: $e');
      return null;
    }
    if (photo == null) return null;

    CroppedFile? cropped;
    try {
      cropped = await _cropper.cropImage(
        sourcePath: photo.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop document',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: Colors.white,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.original,
          ),
          IOSUiSettings(
            title: 'Crop document',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
        ],
      );
    } on Exception catch (e) {
      debugPrint('Document crop failed: $e');
      // The cropper is a convenience; a broken one must not block the scan.
      return File(photo.path);
    }
    if (cropped == null) return null;
    return File(cropped.path);
  }
}
