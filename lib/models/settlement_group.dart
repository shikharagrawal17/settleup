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
  final Map<String, int> netBalances;

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
    };
  }

  factory SettlementGroup.fromJson(String id, Map<String, dynamic> json) {
    final membersJson = (json['members'] as List<dynamic>? ?? [])
        .cast<Map<dynamic, dynamic>>();
    
    final balancesRaw = json['netBalances'] as Map<String, dynamic>? ?? {};
    final netBalances = balancesRaw.map(
      (key, value) => MapEntry(key, (value as num).toInt()),
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
