import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Auto-detected expense categories with icons.
enum ExpenseCategory {
  food(Icons.restaurant_outlined, 'Food'),
  drinks(Icons.local_bar_outlined, 'Drinks'),
  groceries(Icons.shopping_cart_outlined, 'Groceries'),
  transport(Icons.directions_car_outlined, 'Transport'),
  travel(Icons.flight_outlined, 'Travel'),
  stay(Icons.hotel_outlined, 'Stay'),
  shopping(Icons.shopping_bag_outlined, 'Shopping'),
  entertainment(Icons.movie_outlined, 'Entertainment'),
  rent(Icons.home_outlined, 'Rent'),
  bills(Icons.receipt_outlined, 'Bills'),
  medical(Icons.medical_services_outlined, 'Medical'),
  education(Icons.school_outlined, 'Education'),
  other(Icons.category_outlined, 'Other');

  const ExpenseCategory(this.icon, this.label);
  final IconData icon;
  final String label;

  /// Best-effort auto-detection from description text.
  static ExpenseCategory detect(String description) {
    final lower = description.toLowerCase();
    if (_match(lower, ['dinner', 'lunch', 'breakfast', 'food', 'biryani', 'pizza', 'burger', 'restaurant', 'snack', 'meal', 'chai', 'coffee', 'dosa', 'thali'])) return food;
    if (_match(lower, ['beer', 'drinks', 'cocktail', 'bar', 'wine', 'alcohol', 'pub'])) return drinks;
    if (_match(lower, ['grocery', 'groceries', 'vegetables', 'fruits', 'supermarket', 'kirana'])) return groceries;
    if (_match(lower, ['uber', 'ola', 'cab', 'taxi', 'auto', 'rickshaw', 'fuel', 'petrol', 'diesel', 'gas', 'toll', 'metro', 'bus'])) return transport;
    if (_match(lower, ['flight', 'train', 'travel', 'trip', 'ticket', 'booking'])) return travel;
    if (_match(lower, ['hotel', 'stay', 'airbnb', 'hostel', 'lodge', 'room', 'accommodation'])) return stay;
    if (_match(lower, ['shopping', 'amazon', 'flipkart', 'clothes', 'shoes', 'dress'])) return shopping;
    if (_match(lower, ['movie', 'cinema', 'netflix', 'show', 'concert', 'game', 'tickets'])) return entertainment;
    if (_match(lower, ['rent', 'maintenance', 'society', 'house'])) return rent;
    if (_match(lower, ['electricity', 'water', 'wifi', 'internet', 'recharge', 'bill', 'phone'])) return bills;
    if (_match(lower, ['doctor', 'medicine', 'hospital', 'pharmacy', 'medical'])) return medical;
    if (_match(lower, ['course', 'book', 'class', 'tuition', 'school', 'college'])) return education;
    return other;
  }

  static bool _match(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }
}

class Expense {
  Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.payerId,
    required this.shares,
    required this.createdAt,
    required this.createdBy,
    this.category,
  });

  final String id;
  final String description;
  final double amount;
  final String payerId;
  final Map<String, double> shares;
  final DateTime createdAt;
  final String createdBy;
  final ExpenseCategory? category;

  /// Returns the resolved category — stored or auto-detected.
  ExpenseCategory get resolvedCategory =>
      category ?? ExpenseCategory.detect(description);

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'amount': amount,
      'payerId': payerId,
      'shares': shares,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      if (category != null) 'category': category!.name,
    };
  }

  factory Expense.fromJson(String id, Map<String, dynamic> json) {
    final sharesRaw = json['shares'] as Map<String, dynamic>? ?? {};
    final shares = sharesRaw.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );

    DateTime createdAt;
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else {
      createdAt = DateTime.now();
    }

    ExpenseCategory? category;
    final catRaw = json['category'] as String?;
    if (catRaw != null) {
      category = ExpenseCategory.values
          .where((c) => c.name == catRaw)
          .firstOrNull;
    }

    return Expense(
      id: id,
      description: json['description'] as String? ?? 'Expense',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      payerId: json['payerId'] as String? ?? '',
      shares: shares,
      createdAt: createdAt,
      createdBy: json['createdBy'] as String? ?? '',
      category: category,
    );
  }
}
