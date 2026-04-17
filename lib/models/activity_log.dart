import 'package:cloud_firestore/cloud_firestore.dart';

enum ActivityAction {
  expenseAdded,
  expenseEdited,
  expenseDeleted,
  settlementRecorded,
  settlementConfirmed,
  settlementDisputed,
  groupCreated,
  groupEdited,
  memberAdded,
}

class ActivityLog {
  final String id;
  final String actorId;
  final String actorName;
  final ActivityAction action;
  final String targetName; // Expense description or person name
  final double? amount;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  ActivityLog({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.action,
    required this.targetName,
    this.amount,
    required this.timestamp,
    this.metadata = const {},
  });

  List<String> get changedFields => List<String>.from(metadata['changes'] ?? []);
  double? get oldAmount => (metadata['oldAmount'] as num?)?.toDouble();

  factory ActivityLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ActivityLog(
      id: doc.id,
      actorId: data['actorId'] ?? '',
      actorName: data['actorName'] ?? 'Someone',
      action: ActivityAction.values.firstWhere(
        (e) => e.toString() == data['action'],
        orElse: () => ActivityAction.expenseAdded,
      ),
      targetName: data['targetName'] ?? '',
      amount: (data['amount'] as num?)?.toDouble(),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      metadata: data['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'actorId': actorId,
      'actorName': actorName,
      'action': action.toString(),
      'targetName': targetName,
      'amount': amount,
      'timestamp': Timestamp.fromDate(timestamp),
      'metadata': metadata,
    };
  }
}
