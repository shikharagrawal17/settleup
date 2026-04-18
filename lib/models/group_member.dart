class GroupMember {
  GroupMember({
    required this.id,
    required this.name,
    this.phoneNumber,
    this.upiId,
    this.uid, // The Firebase Auth UID if this member is a registered user
    this.photoUrl,
    this.isSelf = false,
  });

  final String id;
  final String name;
  final String? phoneNumber;
  final String? upiId;
  final String? uid;
  final String? photoUrl;
  final bool isSelf;

  GroupMember copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? upiId,
    String? photoUrl,
    bool? isSelf,
  }) {
    return GroupMember(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      upiId: upiId ?? this.upiId,
      uid: uid ?? this.uid,
      photoUrl: photoUrl ?? this.photoUrl,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'upiId': upiId,
      'uid': uid,
      'photoUrl': photoUrl,
      'isSelf': isSelf,
    };
  }

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Member',
      phoneNumber: json['phoneNumber'] as String?,
      upiId: json['upiId'] as String?,
      uid: json['uid'] as String?,
      photoUrl: json['photoUrl'] as String?,
      isSelf: json['isSelf'] as bool? ?? false,
    );
  }
}
