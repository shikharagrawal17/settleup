import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CurrencyHelper {
  static final Map<String, Map<String, double>> _cachedRates = {};
  static final Map<String, DateTime> _lastFetchByBase = {};

  static Future<double> convert({
    required double amount,
    required String from,
    required String to,
  }) async {
    if (from.toUpperCase() == to.toUpperCase()) return amount;

    try {
      final rates = await getRates(to.toUpperCase());
      if (rates != null && rates.containsKey(from.toUpperCase())) {
        // rates are relative to base 'to', so 1 'to' = X 'from'
        // we want to convert 'from' to 'to', so amount / rate
        return amount / rates[from.toUpperCase()]!;
      }
    } catch (e) {
      debugPrint('Currency conversion error: $e');
    }
    return amount; // Fallback to 1:1 if API fails
  }

  static Future<Map<String, double>?> getRates(String base) async {
    final key = base.toUpperCase();
    final lastFetch = _lastFetchByBase[key];
    final cached = _cachedRates[key];

    // Cache rates for 1 hour to stay within free tier and speed up UI
    if (cached != null && lastFetch != null && DateTime.now().difference(lastFetch).inHours < 1) {
      return cached;
    }

    try {
      final response = await http.get(Uri.parse('https://api.exchangerate-api.com/v4/latest/$key'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rates = (data['rates'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
        _cachedRates[key] = rates;
        _lastFetchByBase[key] = DateTime.now();
        return rates;
      }
    } catch (e) {
      debugPrint('Error fetching rates for $key: $e');
    }
    return cached;
  }
}
