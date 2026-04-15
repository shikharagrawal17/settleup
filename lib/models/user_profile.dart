class UserProfile {
  UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.upiId,
    this.phoneNumber,
    this.photoUrl,
    this.isPhoneVerified = false,
  });

  final String uid;
  final String displayName;
  final String email;
  final String upiId;
  final String? phoneNumber;
  final String? photoUrl;
  final bool isPhoneVerified;

  bool get hasUpiId => upiId.trim().isNotEmpty;
  bool get hasPhoneNumber =>
      phoneNumber != null && phoneNumber!.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'email': email,
      'upiId': upiId,
      'phoneNumber': phoneNumber,
      'photoUrl': photoUrl,
      'isPhoneVerified': isPhoneVerified,
    };
  }

  factory UserProfile.fromJson(String uid, Map<String, dynamic> json) {
    return UserProfile(
      uid: uid,
      displayName: json['displayName'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      upiId: json['upiId'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String?,
      photoUrl: json['photoUrl'] as String?,
      isPhoneVerified: json['isPhoneVerified'] as bool? ?? false,
    );
  }
}
