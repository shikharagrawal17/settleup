import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../models/expense.dart';
import '../services/gemini_service.dart';

class OcrResult {
  final double? amount;
  final String? date;
  final String? description;
  final ExpenseCategory? category;
  final List<ReceiptLineItem> items;
  final String? provider;

  OcrResult({
    this.amount,
    this.date,
    this.description,
    this.category,
    this.items = const [],
    this.provider,
  });
}

class OcrHelper {
  static TextRecognizer? _textRecognizer;

  static TextRecognizer get _recognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  /// Scans receipt using Google Gemini 3.5 Flash multimodal vision
  /// with automatic fallback to ML Kit if offline or key is missing.
  static Future<OcrResult?> scanReceipt({
    ImageSource source = ImageSource.camera,
  }) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (image == null) return null;

      final Uint8List bytes = await image.readAsBytes();
      final String mimeType = image.mimeType ?? 'image/jpeg';

      // 1. Attempt High-Precision Gemini 3.5 Flash analysis
      final apiKey = await GeminiService.getApiKey();
      if (apiKey != null && apiKey.isNotEmpty) {
        try {
          final geminiResult = await GeminiService.analyzeReceipt(
            imageBytes: bytes,
            mimeType: mimeType,
          );

          return OcrResult(
            amount: geminiResult.totalAmount,
            date: geminiResult.date,
            description: geminiResult.merchantName ?? geminiResult.rawSummary,
            category: geminiResult.category,
            items: geminiResult.items,
            provider: 'Google Gemini 3.5 Flash',
          );
        } catch (geminiError) {
          debugPrint('[OcrHelper] Gemini scan error, attempting local ML Kit fallback: $geminiError');
        }
      }

      // 2. Fallback to Google ML Kit (Mobile only)
      if (kIsWeb) {
        debugPrint('[OcrHelper] Web platform requires Gemini API key for OCR.');
        return null;
      }

      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _recognizer.processImage(inputImage);

      double? detectedAmount;
      String? detectedDate;
      String? detectedDescription;

      final RegExp amountRegExp = RegExp(r'(\d+\.\d{2})');

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final text = line.text.toLowerCase();

          if (text.contains('total') || text.contains('amount') || text.contains('sum') || text.contains('net')) {
            final match = amountRegExp.firstMatch(line.text);
            if (match != null) {
              detectedAmount = double.tryParse(match.group(1)!);
            }
          }

          final dateRegExp = RegExp(r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})');
          final dateMatch = dateRegExp.firstMatch(line.text);
          if (dateMatch != null) {
            detectedDate = dateMatch.group(1);
          }

          detectedDescription ??= line.text;
        }
      }

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
        category: detectedDescription != null ? ExpenseCategory.detect(detectedDescription) : null,
        provider: 'Google ML Kit',
      );
    } catch (e) {
      debugPrint('[OcrHelper] Scan error: $e');
      return null;
    }
  }

  static void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
