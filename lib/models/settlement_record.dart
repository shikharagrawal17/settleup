import 'package:cloud_firestore/cloud_firestore.dart';

enum SettlementStatus {
  pending,
  confirmed,
  disputed;

  static SettlementStatus fromString(String? val) {
    return SettlementStatus.values.firstWhere((e) => e.name == val, orElse: () => SettlementStatus.pending);
  }
}

class SettlementRecord {
  SettlementRecord({
    required this.id,
    required this.fromMemberId,
    required this.fromName,
    required this.toMemberId,
    required this.toName,
    required this.amount,
    required this.settledAt,
    required this.createdBy,
    this.status = SettlementStatus.pending,
    this.note,
  });

  final String id;
  final String fromMemberId;
  final String fromName;
  final String toMemberId;
  final String toName;
  final double amount;
  final DateTime settledAt;
  final String createdBy;
  final SettlementStatus status;
  final String? note;

  bool get isConfirmed => status == SettlementStatus.confirmed;
  bool get isPending => status == SettlementStatus.pending;
  bool get isDisputed => status == SettlementStatus.disputed;

  Map<String, dynamic> toJson() {
    return {
      'fromMemberId': fromMemberId,
      'fromName': fromName,
      'toMemberId': toMemberId,
      'toName': toName,
      'amount': amount,
      'settledAt': Timestamp.fromDate(settledAt),
      'createdBy': createdBy,
      'status': status.name,
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
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      settledAt: settledAt,
      createdBy: json['createdBy'] as String? ?? '',
      status: SettlementStatus.fromString(json['status'] as String?),
      note: json['note'] as String?,
    );
  }
}
