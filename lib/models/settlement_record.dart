import 'package:cloud_firestore/cloud_firestore.dart';

class SettlementRecord {
  SettlementRecord({
    required this.id,
    required this.fromMemberId,
    required this.fromName,
    required this.toMemberId,
    required this.toName,
    required this.amount,
    required this.settledAt,
    this.note,
  });

  final String id;
  final String fromMemberId;
  final String fromName;
  final String toMemberId;
  final String toName;
  final int amount;
  final DateTime settledAt;
  final String? note;

  Map<String, dynamic> toJson() {
    return {
      'fromMemberId': fromMemberId,
      'fromName': fromName,
      'toMemberId': toMemberId,
      'toName': toName,
      'amount': amount,
      'settledAt': Timestamp.fromDate(settledAt),
      'note': note,
    };
  }

  factory SettlementRecord.fromJson(String id, Map<String, dynamic> json) {
    DateTime settledAt;
    final raw = json['settledAt'];
    if (raw is Timestamp) {
      settledAt = raw.toDate();
    } else {
      settledAt = DateTime.now();
    }

    return SettlementRecord(
      id: id,
      fromMemberId: json['fromMemberId'] as String? ?? '',
      fromName: json['fromName'] as String? ?? '',
      toMemberId: json['toMemberId'] as String? ?? '',
      toName: json['toName'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      settledAt: settledAt,
      note: json['note'] as String?,
    );
  }
}
