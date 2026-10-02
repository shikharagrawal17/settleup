import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrResult {
  final double? amount;
  final String? date;
  final String? description;

  OcrResult({this.amount, this.date, this.description});
}

class OcrHelper {
  static TextRecognizer? _textRecognizer;

  static TextRecognizer get _recognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  static Future<OcrResult?> scanReceipt() async {
    if (kIsWeb) return null; // ML Kit OCR is not supported on Flutter Web

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);

      if (image == null) return null;

      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _recognizer.processImage(inputImage);

    double? detectedAmount;
    String? detectedDate;
    String? detectedDescription;

    // Simple heuristic to find total amount
    // Look for patterns like "Total", "Amount", "INR", "$", etc.
    final RegExp amountRegExp = RegExp(r'(\d+\.\d{2})');
    
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        final text = line.text.toLowerCase();
        
        // Find amount
        if (text.contains('total') || text.contains('amount') || text.contains('sum') || text.contains('net')) {
          final match = amountRegExp.firstMatch(line.text);
          if (match != null) {
            detectedAmount = double.tryParse(match.group(1)!);
          }
        }

        // Find date (simple YYYY-MM-DD or DD/MM/YYYY)
        final dateRegExp = RegExp(r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})');
        final dateMatch = dateRegExp.firstMatch(line.text);
        if (dateMatch != null) {
          detectedDate = dateMatch.group(1);
        }

        // Use first line as description if not set
        detectedDescription ??= line.text;
      }
    }

    // If amount still null, take the largest number found that looks like an amount
    if (detectedAmount == null) {
      double maxVal = 0;
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final match = amountRegExp.firstMatch(line.text);
          if (match != null) {
            final val = double.tryParse(match.group(1)!);
            if (val != null && val > maxVal) {
              maxVal = val;
            }
          }
        }
      }
      if (maxVal > 0) detectedAmount = maxVal;
    }

    return OcrResult(
      amount: detectedAmount,
      date: detectedDate,
      description: detectedDescription,
    );
    } catch (e) {
      debugPrint('OCR Scan error: $e');
      return null;
    }
  }

  static void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
