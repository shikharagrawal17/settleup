import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/expense.dart';
import '../models/group_member.dart';

class ReceiptLineItem {
  final String name;
  final double price;
  final int quantity;

  const ReceiptLineItem({
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'quantity': quantity,
  };
}

class GeminiReceiptResult {
  final double? totalAmount;
  final String? merchantName;
  final String? date;
  final ExpenseCategory? category;
  final List<ReceiptLineItem> items;
  final double? tax;
  final String? rawSummary;

  const GeminiReceiptResult({
    this.totalAmount,
    this.merchantName,
    this.date,
    this.category,
    this.items = const [],
    this.tax,
    this.rawSummary,
  });
}

class GeminiSplitPlan {
  final double amount;
  final String description;
  final String? payerMemberId;
  final String? payerName;
  final List<String> participatingMemberIds;
  final ExpenseCategory category;
  final Map<String, double>? customShares;
  final String explanation;

  const GeminiSplitPlan({
    required this.amount,
    required this.description,
    this.payerMemberId,
    this.payerName,
    required this.participatingMemberIds,
    required this.category,
    this.customShares,
    required this.explanation,
  });
}

class GeminiService {
  static const String _prefApiKey = 'gemini_api_key';
  static String? _cachedApiKey;

  /// Retrieves the active Gemini API key from environment or local storage.
  static Future<String?> getApiKey() async {
    // 1. Check in-memory cache
    if (_cachedApiKey != null && _cachedApiKey!.trim().isNotEmpty) {
      return _cachedApiKey!.trim();
    }

    // 2. Check compile-time environment variable
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    if (envKey.isNotEmpty) {
      _cachedApiKey = envKey;
      return envKey;
    }

    // 3. Check SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedKey = prefs.getString(_prefApiKey);
      if (storedKey != null && storedKey.trim().isNotEmpty) {
        _cachedApiKey = storedKey.trim();
        return storedKey.trim();
      }
    } catch (e) {
      debugPrint('[GeminiService] SharedPreferences read error: $e');
    }

    return null;
  }

  /// Sets and persists a user-provided Gemini API key.
  static Future<void> setApiKey(String key) async {
    _cachedApiKey = key.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefApiKey, key.trim());
    } catch (e) {
      debugPrint('[GeminiService] SharedPreferences save error: $e');
    }
  }

  /// Clears stored API key.
  static Future<void> clearApiKey() async {
    _cachedApiKey = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefApiKey);
    } catch (e) {
      debugPrint('[GeminiService] SharedPreferences clear error: $e');
    }
  }

  /// Multimodal Receipt & Bill Analyzer using Gemini 1.5 Flash
  static Future<GeminiReceiptResult> analyzeReceipt({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'Gemini API key is not configured. Please add your Google AI Studio key.',
      );
    }

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        responseMimeType: 'application/json',
      ),
    );

    const prompt = '''
You are an expert financial receipt auditor and invoice parsing assistant.
Analyze this receipt or bill image and extract the key details in strict JSON format.

JSON Schema:
{
  "merchant": "Name of store, restaurant, or vendor (e.g. Starbucks, Swiggy, D-Mart)",
  "totalAmount": 1250.50,
  "date": "YYYY-MM-DD or as printed",
  "category": "One of: food, drinks, groceries, transport, travel, stay, shopping, entertainment, rent, bills, medical, education, other",
  "tax": 50.0,
  "items": [
    {
      "name": "Item description",
      "price": 250.0,
      "quantity": 1
    }
  ],
  "summary": "Brief 1-line note of what was purchased"
}

Important:
- totalAmount MUST be a positive number reflecting the final bill / total payable amount (including taxes).
- If currency is not explicitly printed, assume INR.
- Do not include markdown code block syntax if JSON mode is used, or ensure valid JSON output.
''';

    try {
      final content = Content.multi([
        TextPart(prompt),
        DataPart(mimeType, imageBytes),
      ]);

      final response = await model.generateContent([content]);
      final rawText = response.text;
      if (rawText == null || rawText.isEmpty) {
        throw Exception('Gemini returned an empty response.');
      }

      final jsonStr = _sanitizeJson(rawText);
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      double? totalAmount;
      if (data['totalAmount'] != null) {
        totalAmount = (data['totalAmount'] as num).toDouble();
      }

      double? tax;
      if (data['tax'] != null) {
        tax = (data['tax'] as num).toDouble();
      }

      final merchant = data['merchant'] as String?;
      final date = data['date'] as String?;
      final categoryStr = (data['category'] as String?)?.toLowerCase();

      ExpenseCategory? category;
      if (categoryStr != null) {
        category = ExpenseCategory.values.firstWhere(
          (c) => c.name.toLowerCase() == categoryStr,
          orElse: () => ExpenseCategory.detect(merchant ?? 'expense'),
        );
      }

      final itemsRaw = data['items'] as List<dynamic>? ?? [];
      final List<ReceiptLineItem> items = [];
      for (final item in itemsRaw) {
        if (item is Map<String, dynamic>) {
          items.add(
            ReceiptLineItem(
              name: item['name'] as String? ?? 'Item',
              price: (item['price'] as num?)?.toDouble() ?? 0.0,
              quantity: (item['quantity'] as num?)?.toInt() ?? 1,
            ),
          );
        }
      }

      return GeminiReceiptResult(
        totalAmount: totalAmount,
        merchantName: merchant,
        date: date,
        category: category,
        items: items,
        tax: tax,
        rawSummary: data['summary'] as String?,
      );
    } catch (e) {
      debugPrint('[GeminiService] Receipt parse error: $e');
      rethrow;
    }
  }

  /// Natural Language Smart Split Assistant using Gemini 1.5 Flash
  static Future<GeminiSplitPlan> parseNaturalLanguageExpense({
    required String prompt,
    required List<GroupMember> members,
    String? currentUserId,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'Gemini API key is not configured. Please add your Google AI Studio key.',
      );
    }

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        responseMimeType: 'application/json',
      ),
    );

    final membersJson = members.map((m) => {
      'id': m.id,
      'name': m.name,
      'isSelf': m.isSelf,
    }).toList();

    final systemInstruction = '''
You are an intelligent expense-splitting AI assistant for Bharat Dues / SettleUp.
Your job is to parse conversational expense entries into structured JSON.

Group members list:
${jsonEncode(membersJson)}

User prompt to parse:
"$prompt"

Return strict JSON with this schema:
{
  "amount": 1450.0,
  "description": "Short description (e.g. Team Lunch, Uber to Airport)",
  "category": "One of: food, drinks, groceries, transport, travel, stay, shopping, entertainment, rent, bills, medical, education, other",
  "payerMemberId": "id of the member who paid, or null if uncertain",
  "payerName": "name of payer",
  "participatingMemberIds": ["id1", "id2"],
  "splitType": "equal or custom",
  "customShares": { "id1": 700.0, "id2": 750.0 },
  "explanation": "Friendly 1-line breakdown explaining how the amount is split."
}

Rules:
1. Fuzzy-match mentioned names with the group members list above.
2. If the user says "I paid" or "me", choose the member with isSelf == true (or current user).
3. If no specific participants are mentioned (e.g. "split equally"), include ALL members in participatingMemberIds.
4. amount MUST be a positive number.
5. If specific unequal amounts are mentioned (e.g. "A owes 200 and B owes 300"), populate customShares so their sum equals amount. Otherwise customShares should be null.
''';

    try {
      final response = await model.generateContent([
        Content.text(systemInstruction),
      ]);

      final rawText = response.text;
      if (rawText == null || rawText.isEmpty) {
        throw Exception('Gemini returned an empty response.');
      }

      final jsonStr = _sanitizeJson(rawText);
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final String description = data['description'] as String? ?? 'Shared Expense';

      // Match category
      final categoryStr = (data['category'] as String?)?.toLowerCase();
      final category = ExpenseCategory.values.firstWhere(
        (c) => c.name.toLowerCase() == categoryStr,
        orElse: () => ExpenseCategory.detect(description),
      );

      // Match payer
      String? payerId = data['payerMemberId'] as String?;
      String? payerName = data['payerName'] as String?;

      if (payerId == null || !members.any((m) => m.id == payerId)) {
        if (payerName != null) {
          final matched = members.where(
            (m) => m.name.toLowerCase().contains(payerName.toLowerCase()),
          ).firstOrNull;
          payerId = matched?.id;
        }
      }

      // Default payer to self if still null
      payerId ??= members.where((m) => m.isSelf).firstOrNull?.id ?? members.firstOrNull?.id;

      // Match participants
      final List<dynamic> rawParticipants = data['participatingMemberIds'] as List<dynamic>? ?? [];
      List<String> participatingIds = rawParticipants
          .map((e) => e.toString())
          .where((id) => members.any((m) => m.id == id))
          .toList();

      if (participatingIds.isEmpty) {
        participatingIds = members.map((m) => m.id).toList();
      }

      // Parse custom shares if present
      Map<String, double>? customShares;
      if (data['customShares'] is Map) {
        customShares = {};
        (data['customShares'] as Map).forEach((k, v) {
          if (v is num) {
            customShares![k.toString()] = v.toDouble();
          }
        });
      }

      final explanation = data['explanation'] as String? ??
          '₹${amount.toStringAsFixed(2)} split across ${participatingIds.length} members.';

      return GeminiSplitPlan(
        amount: amount,
        description: description,
        payerMemberId: payerId,
        payerName: members.where((m) => m.id == payerId).firstOrNull?.name,
        participatingMemberIds: participatingIds,
        category: category,
        customShares: customShares,
        explanation: explanation,
      );
    } catch (e) {
      debugPrint('[GeminiService] Split parse error: $e');
      rethrow;
    }
  }

  static String _sanitizeJson(String raw) {
    var s = raw.trim();
    if (s.startsWith('```json')) {
      s = s.substring(7);
    } else if (s.startsWith('```')) {
      s = s.substring(3);
    }
    if (s.endsWith('```')) {
      s = s.substring(0, s.length - 3);
    }
    return s.trim();
  }
}
