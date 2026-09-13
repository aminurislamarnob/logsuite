import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

final ocrServiceProvider = Provider<OcrService>((ref) {
  return const OcrService();
});

class OcrService {
  const OcrService();

  /// Scans the given [imageFile] for Latin text using Google ML Kit.
  /// Returns the full block of recognized text, or null if it fails.
  Future<String?> extractText(File imageFile) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await textRecognizer.processImage(inputImage);
      return recognizedText.text.trim();
    } catch (e) {
      // In a real app we might log this, but for now just return null
      return null;
    } finally {
      textRecognizer.close();
    }
  }
}
