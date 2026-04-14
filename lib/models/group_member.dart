class GroupMember {
  GroupMember({
    required this.id,
    required this.name,
    this.phoneNumber,
    this.upiId,
    this.isSelf = false,
  });

  final String id;
  final String name;
  final String? phoneNumber;
  final String? upiId;
  final bool isSelf;

  GroupMember copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? upiId,
    bool? isSelf,
  }) {
    return GroupMember(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      upiId: upiId ?? this.upiId,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'upiId': upiId,
      'isSelf': isSelf,
    };
  }

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Member',
      phoneNumber: json['phoneNumber'] as String?,
      upiId: json['upiId'] as String?,
      isSelf: json['isSelf'] as bool? ?? false,
    );
  }
}
