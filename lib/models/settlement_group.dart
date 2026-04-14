import 'group_member.dart';

class SettlementGroup {
  SettlementGroup({
    required this.id,
    required this.name,
    required this.members,
    required this.createdBy,
    this.isNonGroup = false,
  });

  final String id;
  final String name;
  final List<GroupMember> members;
  final String createdBy;
  final bool isNonGroup;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'createdBy': createdBy,
      'isNonGroup': isNonGroup,
      'members': members.map((member) => member.toJson()).toList(),
    };
  }

  factory SettlementGroup.fromJson(String id, Map<String, dynamic> json) {
    final membersJson = (json['members'] as List<dynamic>? ?? [])
        .cast<Map<dynamic, dynamic>>();

    return SettlementGroup(
      id: id,
      name: json['name'] as String? ?? 'Untitled Group',
      createdBy: json['createdBy'] as String? ?? '',
      isNonGroup: json['isNonGroup'] as bool? ?? false,
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
