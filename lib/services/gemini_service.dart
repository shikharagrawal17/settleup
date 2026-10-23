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
  final String? description;
  final String? date;
  final ExpenseCategory? category;
  final List<ReceiptLineItem> items;
  final double? tax;
  final String? rawSummary;
  final String? payerMemberId;
  final String? payerName;
  final List<String> participatingMemberIds;
  final String splitType;
  final Map<String, double>? customShares;
  final String? gstin;
  final String? upiRef;
  final String? explanation;
  final String modelUsed;

  const GeminiReceiptResult({
    this.totalAmount,
    this.merchantName,
    this.description,
    this.date,
    this.category,
    this.items = const [],
    this.tax,
    this.rawSummary,
    this.payerMemberId,
    this.payerName,
    this.participatingMemberIds = const [],
    this.splitType = 'equal',
    this.customShares,
    this.gstin,
    this.upiRef,
    this.explanation,
    this.modelUsed = 'gemini-3.5-flash',
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
  final String modelUsed;

  const GeminiSplitPlan({
    required this.amount,
    required this.description,
    this.payerMemberId,
    this.payerName,
    required this.participatingMemberIds,
    required this.category,
    this.customShares,
    required this.explanation,
    this.modelUsed = 'gemini-3.5-flash',
  });
}

class GeminiService {
  static const String _prefApiKey = 'gemini_api_key';
  static String? _cachedApiKey;

  /// Verified active models on Google AI Studio API in priority order
  static const List<String> activeModels = [
    'gemini-3.5-flash',
    'gemini-3.6-flash',
    'gemini-3.8-flash',
  ];

  /// Retrieves the active Gemini API key from environment or local storage.
  static Future<String?> getApiKey() async {
    if (_cachedApiKey != null && _cachedApiKey!.trim().isNotEmpty) {
      return _cachedApiKey!.trim();
    }

    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    if (envKey.isNotEmpty) {
      _cachedApiKey = envKey;
      return envKey;
    }

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

  /// Helper to generate content with automatic model fallback across active Google AI Studio models
  static Future<({String text, String modelUsed})> _generateWithFallback({
    required String apiKey,
    required List<Content> contents,
    GenerationConfig? generationConfig,
  }) async {
    Object? lastError;

    for (final modelName in activeModels) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: generationConfig,
        );

        final response = await model.generateContent(contents);
        final text = response.text;
        if (text != null && text.isNotEmpty) {
          return (text: text, modelUsed: modelName);
        }
      } catch (e) {
        lastError = e;
        debugPrint('[GeminiService] Model $modelName failed ($e), trying next active Google model...');
      }
    }

    throw Exception(
      'All active Google AI Studio models failed. Please verify your API key or network connection. Last error: $lastError',
    );
  }

  /// Multimodal Receipt & Bill Analyzer using active Google AI Studio models
  /// with rich group context for maximum automated field extraction.
  static Future<GeminiReceiptResult> analyzeReceipt({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    List<GroupMember> members = const [],
    String? groupName,
    String? currentUserId,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'Gemini API key is not configured. Please add your Google AI Studio key.',
      );
    }

    final membersJson = members.map((m) => {
      'id': m.id,
      'name': m.name,
      'isSelf': m.isSelf,
    }).toList();

    final prompt = '''
You are an expert financial receipt auditor and expense-splitting intelligence assistant for Bharat Dues / SettleUp.
Analyze this receipt, bill, or UPI payment screenshot and extract maximum context and details in strict JSON format.

Group Context:
- Group Name: "${groupName ?? 'General Group'}"
- Group Members: ${jsonEncode(membersJson)}
- Currency: INR (₹)

JSON Schema:
{
  "merchant": "Name of store, restaurant, vendor, or receiver (e.g. Starbucks, Swiggy, D-Mart, Shell)",
  "description": "Clear 3-5 word description of the expense (e.g. Team Dinner at Starbucks, Groceries at D-Mart)",
  "totalAmount": 1250.50,
  "date": "YYYY-MM-DD or as printed",
  "category": "One of: food, drinks, groceries, transport, travel, stay, shopping, entertainment, rent, bills, medical, education, other",
  "payerMemberId": "id of member from Group Members list who paid, or null if uncertain",
  "payerName": "name of payer",
  "splitType": "equal or exact",
  "participatingMemberIds": ["id1", "id2"],
  "customShares": { "id1": 600.0, "id2": 650.50 },
  "tax": 50.0,
  "gstin": "GST number if printed, or null",
  "upiRef": "UPI reference / UTR number if printed, or null",
  "items": [
    {
      "name": "Item description",
      "price": 250.0,
      "quantity": 1
    }
  ],
  "summary": "Brief 1-line breakdown explaining the expense and how it was split"
}

Important Instructions:
1. totalAmount MUST be a positive number reflecting the final bill / total payable amount (including taxes, discounts, delivery fees).
2. Payer Detection:
   - Check if customer name, cardholder name, UPI sender name ("From: XYZ", "Paid by: ABC"), or account name matches any Group Member.
   - If user paid via their own device (UPI screenshot showing "Paid successfully to...", "Debit from XXXX"), prefer member with isSelf == true.
   - If fuzzy match succeeds, set payerMemberId to that member's ID.
3. Split Ratio & Participants:
   - If bill indicates specific items for specific members, populate customShares for those member IDs so their sum equals totalAmount, and set splitType = "exact".
   - Otherwise, default splitType to "equal" and include ALL members in participatingMemberIds.
4. If currency is not explicitly printed, assume INR.
5. Return valid JSON only.
''';

    try {
      final content = Content.multi([
        TextPart(prompt),
        DataPart(mimeType, imageBytes),
      ]);

      final result = await _generateWithFallback(
        apiKey: apiKey,
        contents: [content],
        generationConfig: GenerationConfig(
          temperature: 0.1,
          responseMimeType: 'application/json',
        ),
      );

      final jsonStr = _sanitizeJson(result.text);
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
      final description = data['description'] as String? ?? merchant ?? 'Receipt Expense';
      final date = data['date'] as String?;
      final categoryStr = (data['category'] as String?)?.toLowerCase();

      ExpenseCategory? category;
      if (categoryStr != null) {
        category = ExpenseCategory.values.firstWhere(
          (c) => c.name.toLowerCase() == categoryStr,
          orElse: () => ExpenseCategory.detect(description),
        );
      } else {
        category = ExpenseCategory.detect(description);
      }

      // Match Payer against group members
      String? payerId = data['payerMemberId'] as String?;
      final String? payerName = data['payerName'] as String?;
      if (payerId == null || !members.any((m) => m.id == payerId)) {
        if (payerName != null && payerName.isNotEmpty) {
          final matched = members.where(
            (m) => m.name.toLowerCase().contains(payerName.toLowerCase()) ||
                   payerName.toLowerCase().contains(m.name.toLowerCase()),
          ).firstOrNull;
          payerId = matched?.id;
        }
      }

      // Default payer to isSelf if ambiguous
      payerId ??= members.where((m) => m.isSelf).firstOrNull?.id;

      // Match participating members
      final List<dynamic> rawParticipants = data['participatingMemberIds'] as List<dynamic>? ?? [];
      List<String> participatingIds = rawParticipants
          .map((e) => e.toString())
          .where((id) => members.any((m) => m.id == id))
          .toList();

      if (participatingIds.isEmpty && members.isNotEmpty) {
        participatingIds = members.map((m) => m.id).toList();
      }

      final splitType = data['splitType'] as String? ?? 'equal';

      // Custom shares if itemized or unequal
      Map<String, double>? customShares;
      if (data['customShares'] is Map) {
        customShares = {};
        (data['customShares'] as Map).forEach((k, v) {
          if (v is num && members.any((m) => m.id == k.toString())) {
            customShares![k.toString()] = v.toDouble();
          }
        });
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

      final gstin = data['gstin'] as String?;
      final upiRef = data['upiRef'] as String?;
      final summary = data['summary'] as String?;

      return GeminiReceiptResult(
        totalAmount: totalAmount,
        merchantName: merchant,
        description: description,
        date: date,
        category: category,
        items: items,
        tax: tax,
        rawSummary: summary,
        payerMemberId: payerId,
        payerName: members.where((m) => m.id == payerId).firstOrNull?.name ?? payerName,
        participatingMemberIds: participatingIds,
        splitType: splitType,
        customShares: customShares,
        gstin: gstin,
        upiRef: upiRef,
        explanation: summary,
        modelUsed: result.modelUsed,
      );
    } catch (e) {
      debugPrint('[GeminiService] Receipt parse error: $e');
      rethrow;
    }
  }

  /// Natural Language Smart Split Assistant using active Google AI Studio models
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
      final result = await _generateWithFallback(
        apiKey: apiKey,
        contents: [Content.text(systemInstruction)],
        generationConfig: GenerationConfig(
          temperature: 0.1,
          responseMimeType: 'application/json',
        ),
      );

      final jsonStr = _sanitizeJson(result.text);
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
      final String? payerName = data['payerName'] as String?;

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
        modelUsed: result.modelUsed,
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
