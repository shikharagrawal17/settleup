import 'group_member.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettlementGroup {
  SettlementGroup({
    required this.id,
    required this.name,
    required this.members,
    required this.createdBy,
    this.isNonGroup = false,
    this.isDeleted = false,
    this.createdAt,
    this.updatedAt,
    this.lastActionBy,
    this.lastActionType,
    this.netBalances = const {},
    this.totalSpent = 0.0,
    this.currency = 'INR',
  });

  final String id;
  final String name;
  final List<GroupMember> members;
  final String createdBy;
  final bool isNonGroup;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? lastActionBy;
  final String? lastActionType;
  final Map<String, double> netBalances;
  final double totalSpent;
  final String currency;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'createdBy': createdBy,
      'isNonGroup': isNonGroup,
      'isDeleted': isDeleted,
      'lastActionBy': lastActionBy,
      'lastActionType': lastActionType,
      'members': members.map((member) => member.toJson()).toList(),
      'netBalances': netBalances,
      'totalSpent': totalSpent,
      'currency': currency,
    };
  }

  factory SettlementGroup.fromJson(String id, Map<String, dynamic> json) {
    final membersJson = (json['members'] as List<dynamic>? ?? [])
        .cast<Map<dynamic, dynamic>>();
    
    final balancesRaw = json['netBalances'] as Map<String, dynamic>? ?? {};
    final netBalances = balancesRaw.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );

    DateTime? parseDate(dynamic d) {
      if (d is Timestamp) return d.toDate();
      if (d is String) return DateTime.tryParse(d);
      return null;
    }

    return SettlementGroup(
      id: id,
      name: json['name'] as String? ?? 'Untitled Group',
      createdBy: json['createdBy'] as String? ?? '',
      isNonGroup: json['isNonGroup'] as bool? ?? false,
      isDeleted: json['isDeleted'] as bool? ?? false,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      lastActionBy: json['lastActionBy'] as String?,
      lastActionType: json['lastActionType'] as String?,
      netBalances: netBalances,
      totalSpent: (json['totalSpent'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'INR',
      members: membersJson
          .map(
            (member) => GroupMember.fromJson(
              Map<String, dynamic>.from(member),
            ),
          )
          .toList(),
    );
  }
}
