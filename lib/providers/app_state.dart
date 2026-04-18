import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/expense.dart';
import '../models/group_member.dart';
import '../models/settlement_group.dart';
import '../models/settlement_record.dart';
import '../models/user_profile.dart';
import '../models/activity_log.dart';
import '../utils/upi_helper.dart';

class AppState extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _initializingGoogle = false;
  bool _isSigningIn = false;
  String? _authError;
  Map<String, String> _localContactMap = {};
  List<GroupMember> _googleContacts = [];
  List<GroupMember> get googleContacts => _googleContacts;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/contacts.readonly',
    ],
  );
  StreamSubscription<User?>? _userSub;

  AppState() {
    _initAuth();
  }

  void _initAuth() {
    _userSub = _auth.authStateChanges().listen((user) async {
       if (user != null) {
         _ensureUserProfile(user);
       } else if (kIsWeb) {
         // Silently try to sign in with Google on web if not authenticated
         try {
           final googleUser = await _googleSignIn.signInSilently();
           if (googleUser != null) {
              final auth = await googleUser.authentication;
              final cred = GoogleAuthProvider.credential(
                idToken: auth.idToken,
                accessToken: auth.accessToken,
              );
              await _auth.signInWithCredential(cred);
           }
         } catch (e) {
           debugPrint('Silent sign-in failed: $e');
         }
       }
       notifyListeners();
    });
    loadLocalContacts();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  bool get isSigningIn => _isSigningIn;
  String? get authError => _authError;

  Future<void> loadLocalContacts() async {
    if (kIsWeb) return; // Browsers don't have native local contacts
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted) return;

      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );
      final Map<String, String> resolved = {};
      for (final contact in contacts) {
        for (final phone in contact.phones) {
          final normalised = AppState.normalisePhone(phone.number);
          if (normalised.isNotEmpty) {
            resolved[normalised] = contact.displayName ?? 'Unknown Contact';
          }
        }
      }
      _localContactMap = resolved;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading contacts: $e');
    }
  }

  Future<void> fetchGoogleContacts() async {
    try {
      final googleUser = await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (googleUser == null) return;

      final authHeaders = await googleUser.authHeaders;
      final response = await http.get(
        Uri.parse('https://people.googleapis.com/v1/people/me/connections?personFields=names,phoneNumbers'),
        headers: authHeaders,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List connections = data['connections'] ?? [];
        
        final List<GroupMember> resolved = [];
        for (final c in connections) {
          final names = c['names'] as List?;
          final name = names != null && names.isNotEmpty ? names[0]['displayName'] ?? 'Unknown' : 'Unknown';
          
          final phones = c['phoneNumbers'] as List?;
          if (phones != null && phones.isNotEmpty) {
             for (final p in phones) {
               final phone = p['value'] as String?;
               if (phone != null) {
                 resolved.add(GroupMember(
                   id: 'google_${c['recordId'] ?? DateTime.now().millisecondsSinceEpoch}_${resolved.length}',
                   name: name,
                   phoneNumber: phone,
                 ));
               }
             }
          }
        }
        _googleContacts = resolved;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching Google contacts: $e');
    }
  }

  String resolveMemberName(GroupMember member) {
    // Only return 'You' if the ID actually matches the current user's UID 
    // or if it's explicitly marked as self AND it's truly the current user.
    final currentUid = _auth.currentUser?.uid;
    if (member.id == currentUid || (member.uid != null && member.uid == currentUid)) {
      return 'You';
    }
    
    if (member.phoneNumber != null) {
      final normalised = AppState.normalisePhone(member.phoneNumber!);
      if (_localContactMap.containsKey(normalised)) {
        return _localContactMap[normalised]!;
      }
    }
    return member.name;
  }
  FirebaseAuth get auth => _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> initMessaging() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      // Request for iOS primarily
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      
      final token = await messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('FCM Error: $e');
    }
  }

  Future<void> signInWithGoogle() async {
    _authError = null;
    _isSigningIn = true;
    notifyListeners();

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isSigningIn = false;
        notifyListeners();
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      await _ensureUserProfile(userCredential.user);
    } on FirebaseAuthException catch (error) {
      _authError = error.message ?? error.code;
    } catch (error) {
      _authError = error.toString();
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  String? _verificationId;

  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) codeSent,
    required Function(String error) verificationFailed,
  }) async {
    _authError = null;
    notifyListeners();

    await _auth.verifyPhoneNumber(
      phoneNumber: AppState.normalisePhone(phoneNumber),
      verificationCompleted: (PhoneAuthCredential credential) async {
        final userCredential = await _auth.signInWithCredential(credential);
        await _ensureUserProfile(userCredential.user);
      },
      verificationFailed: (e) {
        _authError = e.message;
        notifyListeners();
        verificationFailed(e.message ?? 'Verification failed');
      },
      codeSent: (String vid, int? token) {
        _verificationId = vid;
        codeSent(vid, token);
      },
      codeAutoRetrievalTimeout: (String vid) {
        _verificationId = vid;
      },
    );
  }

  Future<void> signInWithOtp(String smsCode) async {
    if (_verificationId == null) return;
    
    _isSigningIn = true;
    _authError = null;
    notifyListeners();
    
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      await _ensureUserProfile(userCredential.user);
    } on FirebaseAuthException catch (e) {
      _authError = e.message;
    } catch (e) {
      _authError = e.toString();
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> _ensureUserProfile(User? user) async {
    if (user == null) return;

    final doc = _userDoc(user.uid);
    final snapshot = await doc.get();

    final normalizedEmail = (user.email ?? '').toLowerCase();

    if (snapshot.exists) {
      await doc.set(
        {
          'displayName': user.displayName ?? 'User',
          'email': normalizedEmail,
          'photoUrl': user.photoURL,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _upsertPublicProfile(
        uid: user.uid,
        displayName: user.displayName ?? 'User',
        photoUrl: user.photoURL,
        upiId: null,
        phoneNumber: user.phoneNumber,
      );
      if (normalizedEmail.isNotEmpty) {
        await _upsertRegistry(key: 'email_$normalizedEmail', uid: user.uid);
      }
      return;
    }

    await doc.set({
      'displayName': user.displayName ?? 'User',
      'email': normalizedEmail,
      'photoUrl': user.photoURL,
      'phoneNumber': user.phoneNumber ?? '',
      'upiId': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _upsertPublicProfile(
      uid: user.uid,
      displayName: user.displayName ?? 'User',
      photoUrl: user.photoURL,
      upiId: '',
      phoneNumber: user.phoneNumber,
    );
    if (normalizedEmail.isNotEmpty) {
      await _upsertRegistry(key: 'email_$normalizedEmail', uid: user.uid);
    }
  }

  // ─── User profile ──────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  Stream<UserProfile?> profileStream(String uid) {
    return _userDoc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return UserProfile.fromJson(uid, data);
    });
  }

  DocumentReference<Map<String, dynamic>> _publicUserDoc(String uid) {
    return _firestore.collection('publicUsers').doc(uid);
  }

  Future<void> _upsertPublicProfile({
    required String uid,
    required String displayName,
    required String? photoUrl,
    required String? upiId,
    required String? phoneNumber,
  }) async {
    final Map<String, dynamic> data = {
      'displayName': displayName,
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (upiId != null) {
      final trimmed = upiId.trim();
      if (trimmed.isNotEmpty && trimmed.contains('@')) {
        data['upiId'] = trimmed;
      }
    }
    if (phoneNumber != null) data['phoneNumber'] = normalisePhone(phoneNumber);
    await _publicUserDoc(uid).set(data, SetOptions(merge: true));
  }

  /// Real-time stream for multiple user profiles by ID OR Phone.
  /// Used for resolving names and UPI IDs in groups.
  Stream<Map<String, UserProfile>> profilesStream(List<String> identifiers) {
    if (identifiers.isEmpty) return Stream.value({});
    
    return _firestore
        .collection('publicUsers')
        .snapshots()
        .map((snap) {
      final Map<String, UserProfile> result = {};
      
      // Pre-normalise all input identifiers for comparison
      final normalisedIdentifiers = identifiers.map((id) => normalisePhone(id)).toSet();

      for (final doc in snap.docs) {
        final profile = UserProfile.fromJson(doc.id, doc.data());
        
        // Match by UID (doc ID)
        if (identifiers.contains(doc.id)) {
          result[doc.id] = profile;
        }

        // Match by Normalised Phone Number (check if profile phone matches ANY requested identifier)
        if (profile.phoneNumber != null) {
          final pPhone = normalisePhone(profile.phoneNumber!);
          if (normalisedIdentifiers.contains(pPhone)) {
             // We map both the UID and the phone variants to this profile
             result[doc.id] = profile;
             result[pPhone] = profile;
             // Also support the raw version if it was in the identifiers
             for (final id in identifiers) {
               if (normalisePhone(id) == pPhone) {
                 result[id] = profile;
               }
             }
          }
        }
      }
      return result;
    });
  }

  Future<void> _upsertRegistry({required String key, required String uid}) async {
    await _firestore.collection('registries').doc(key).set(
      {'uid': uid, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String? phoneNumber,
    required String upiId,
  }) async {
    await _userDoc(uid).set({
      'displayName': displayName,
      'phoneNumber': phoneNumber != null ? normalisePhone(phoneNumber) : null,
      'upiId': upiId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveProfile({String? upiId, String? phoneNumber}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final normalizedPhone = phoneNumber != null ? normalisePhone(phoneNumber) : null;
    final normalizedEmail = (user.email ?? '').toLowerCase();

    await _firestore.runTransaction((transaction) async {
      final userRef = _userDoc(user.uid);
      final userSnap = await transaction.get(userRef);
      final oldPhone = userSnap.data()?['phoneNumber'] as String?;

      if (normalizedPhone != null && normalizedPhone != oldPhone) {
        // Check if phone is already taken in the registry
        final regRef = _firestore.collection('registries').doc('phone_$normalizedPhone');
        final regSnap = await transaction.get(regRef);
        if (regSnap.exists && regSnap.data()?['uid'] != user.uid) {
          throw Exception('This phone number is already registered with another account.');
        }
        
        // Update registry: remove old, add new
        if (oldPhone != null && oldPhone.isNotEmpty) {
          transaction.delete(_firestore.collection('registries').doc('phone_$oldPhone'));
        }
        transaction.set(regRef, {'uid': user.uid, 'updatedAt': FieldValue.serverTimestamp()});
      }

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (upiId != null) updates['upiId'] = upiId.trim();
      if (normalizedPhone != null) updates['phoneNumber'] = normalizedPhone;

      transaction.update(userRef, updates);

      // Keep public profile (minimal) and email registry up-to-date.
      transaction.set(_publicUserDoc(user.uid), {
        'displayName': userSnap.data()?['displayName'] ?? user.displayName ?? 'User',
        if (upiId != null) 'upiId': upiId.trim(),
        'photoUrl': userSnap.data()?['photoUrl'] ?? user.photoURL,
        'phoneNumber': normalizedPhone ?? userSnap.data()?['phoneNumber'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (normalizedEmail.isNotEmpty) {
        transaction.set(
          _firestore.collection('registries').doc('email_$normalizedEmail'),
          {'uid': user.uid, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> saveUpiId(String upiId) => saveProfile(upiId: upiId);

  // ─── Contact lookup ──────────────────────────────────────────────────────

  Future<UserProfile?> lookupUserByContact(String contact) async {
    final queryText = contact.trim();
    if (queryText.isEmpty) return null;

    final isEmail = queryText.contains('@');
    final queryValue = isEmail ? queryText.toLowerCase() : normalisePhone(queryText);

    if (queryValue.isEmpty) return null;

    final registryKey = isEmail ? 'email_$queryValue' : 'phone_$queryValue';
    final regSnap =
        await _firestore.collection('registries').doc(registryKey).get();
    final uid = regSnap.data()?['uid'] as String?;
    if (uid == null || uid.isEmpty) return null;

    final publicSnap = await _publicUserDoc(uid).get();
    final publicData = publicSnap.data();
    if (publicData == null) return null;

    return UserProfile(
      uid: uid,
      displayName: publicData['displayName'] as String? ?? 'User',
      email: '',
      upiId: publicData['upiId'] as String? ?? '',
      phoneNumber: null,
      photoUrl: publicData['photoUrl'] as String?,
    );
  }

  static String normalisePhone(String raw) {
    if (raw.trim().isEmpty) return '';
    if (raw.contains('@')) return raw.toLowerCase().trim();
    
    // If it contains letters, it's a UID, not a phone number
    if (raw.contains(RegExp(r'[a-zA-Z]'))) return raw.trim();

    // Trim all whitespace, dashes, and parentheses
    var cleaned = raw.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    if (cleaned.isEmpty) return cleaned;

    // Handle missing country code
    // If it starts with 0, replace with +91
    if (cleaned.startsWith('0')) {
      cleaned = '+91${cleaned.substring(1)}';
    } 
    // If it's 10 digits and doesn't start with +, assume India (+91)
    else if (cleaned.length == 10 && !cleaned.startsWith('+')) {
      cleaned = '+91$cleaned';
    }
    // If it starts with 91 but no +, add +
    else if (cleaned.startsWith('91') && cleaned.length > 10 && !cleaned.startsWith('+')) {
      cleaned = '+$cleaned';
    }
    // Final check: if it doesn't start with + and is long enough, prepend it
    else if (!cleaned.startsWith('+') && cleaned.length >= 10) {
      cleaned = '+91$cleaned';
    }

    return cleaned;
  }

  // ─── Shared group collection ───────────────────────────────────────────
  //
  // Firestore path: groups/{groupId}
  //   - memberIds: [uid, uid, ...]   ← used for querying & security rules
  //   - members:   [{ id, name, ... }]
  //   - name, createdBy, createdAt
  //   - expenses subcollection
  //   - settlements subcollection
  //
  // Every member of the group reads and writes to the SAME document, so all
  // changes are instantly visible to everyone — just like Splitwise.

  CollectionReference<Map<String, dynamic>> get _groupsCol =>
      _firestore.collection('groups');

  DocumentReference<Map<String, dynamic>> _groupDoc(String groupId) =>
      _groupsCol.doc(groupId);

  // ─── Group streams ────────────────────────────────────────────────────

  /// All groups where the current user is a member, ordered by name.
  Stream<List<SettlementGroup>> groupsStream({required String uid, String? phoneNumber}) {
    // Collect all possible identifiers for the user
    final identifiers = <String>[uid];
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      identifiers.add(normalisePhone(phoneNumber));
    }

    return _groupsCol
        .where('memberIdentifiers', arrayContainsAny: identifiers)
        .snapshots()
        .map((snap) {
      final items = snap.docs
          .map((doc) => SettlementGroup.fromJson(doc.id, doc.data()))
          .where((g) {
            // Soft delete check
            final doc = snap.docs.firstWhere((d) => d.id == g.id);
            return doc.data()['isDeleted'] != true;
          })
          .toList();
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    });
  }

  // ─── Activity Logs ─────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _activitiesCol(String groupId) =>
      _groupDoc(groupId).collection('activities');

  Stream<List<ActivityLog>> activitiesStream(String groupId) {
    return _activitiesCol(groupId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => ActivityLog.fromFirestore(doc)).toList());
  }

  Future<void> _logActivity({
    required String groupId,
    required ActivityAction action,
    required String targetName,
    double? amount,
    Map<String, dynamic> metadata = const {},
    WriteBatch? batch,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // We fetch the name from the current user profile in the group members ideally,
    // but for simplicity we'll just use the auth name or generic.
    final log = ActivityLog(
      id: '', // Not needed for set
      actorId: user.uid,
      actorName: user.displayName ?? 'Summary',
      actorPhotoUrl: user.photoURL,
      action: action,
      targetName: targetName,
      amount: amount,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    if (batch != null) {
      batch.set(_activitiesCol(groupId).doc(), log.toFirestore());
    } else {
      await _activitiesCol(groupId).add(log.toFirestore());
    }
  }

  /// Single group stream — used to detect edits made by other members.
  Stream<SettlementGroup?> groupStream(String groupId) {
    return _groupDoc(groupId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return SettlementGroup.fromJson(snap.id, data);
    });
  }

  // ─── Group CRUD ────────────────────────────────────────────────────────

  Future<void> createGroup({
    required UserProfile profile,
    required String name,
    required List<GroupMember> members,
    bool isNonGroup = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final selfMember = GroupMember(
      id: user.uid,
      name: profile.displayName,
      phoneNumber: profile.phoneNumber,
      upiId: profile.upiId,
      photoUrl: profile.photoUrl,
      isSelf: true,
    );

    final normalizedMembers = <GroupMember>[
      selfMember,
      ...members.where((m) => m.id != user.uid).map((m) => GroupMember(
        id: m.id,
        name: m.name,
        phoneNumber: m.phoneNumber != null ? normalisePhone(m.phoneNumber!) : null,
        upiId: m.upiId,
      )),
    ];

    // Collect all member UIDs and phone numbers for global lookup.
    final memberIds = normalizedMembers.map((m) => m.id).toList();
    final memberLogins = normalizedMembers.where((m) => m.uid != null).map((m) => m.uid!).toList();
    
    final memberIdentifiers = <String>{};
    for (final m in normalizedMembers) {
      memberIdentifiers.add(m.id);
      if (m.uid != null) memberIdentifiers.add(m.uid!);
      if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
        memberIdentifiers.add(m.phoneNumber!);
      }
    }

    await _groupsCol.add({
      'name': name.trim(),
      'createdBy': user.uid,
      'isNonGroup': isNonGroup,
      'memberIds': memberIds,
      'memberLogins': memberLogins,
      'memberIdentifiers': memberIdentifiers.toList(),
      'members': normalizedMembers.map((m) => m.toJson()).toList(),
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGroup(String groupId) async {
    await _groupDoc(groupId).set(
      {'isDeleted': true, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> restoreGroup(String groupId) async {
    await _groupDoc(groupId).set(
      {'isDeleted': false, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> updateGroupName({
    required String groupId,
    required String name,
  }) async {
    await _groupDoc(groupId).set(
      {'name': name.trim(), 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await _logActivity(
      groupId: groupId,
      action: ActivityAction.groupEdited,
      targetName: name.trim(),
    );
  }

  Future<void> updateGroupMembers({
    required String groupId,
    required List<GroupMember> members,
    String? newCreatorId,
  }) async {
    final normalized = members.map((m) => GroupMember(
      id: m.id,
      name: m.name,
      phoneNumber: m.phoneNumber != null ? normalisePhone(m.phoneNumber!) : null,
      upiId: m.upiId,
      isSelf: m.isSelf,
    )).toList();

    final memberIds = normalized.map((m) => m.id).toList();
    final memberIdentifiers = <String>{};
    for (final m in normalized) {
      memberIdentifiers.add(m.id);
      if (m.uid != null) memberIdentifiers.add(m.uid!);
      if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
        memberIdentifiers.add(m.phoneNumber!);
      }
    }

    final Map<String, dynamic> data = {
      'members': normalized.map((m) => m.toJson()).toList(),
      'memberIds': memberIds, // Accounting IDs
      'memberLogins': normalized.where((m) => m.uid != null).map((m) => m.uid!).toList(), // Extra for security rules
      'memberIdentifiers': memberIdentifiers.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (newCreatorId != null) {
      data['createdBy'] = newCreatorId;
    }

    await _groupDoc(groupId).set(
      data,
      SetOptions(merge: true),
    );
    await _logActivity(
      groupId: groupId,
      action: ActivityAction.groupEdited,
      targetName: "group members",
    );
  }

  // ─── Expense CRUD ──────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _expensesCol(String groupId) =>
      _groupDoc(groupId).collection('expenses');

  Stream<List<Expense>> expensesStream(String groupId) {
    return _expensesCol(groupId)
        .snapshots()
        .map((snap) {
          final items = snap.docs.map((doc) => Expense.fromJson(doc.id, doc.data())).toList();
          items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return items;
        });
  }

  Future<void> addExpense({
    required String groupId,
    required Expense expense,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Attach creator
    final expenseData = expense.toJson();
    expenseData['createdBy'] = user.uid;

    final batch = _firestore.batch();
    batch.set(_expensesCol(groupId).doc(), expenseData);
    batch.update(_groupDoc(groupId), {'updatedAt': FieldValue.serverTimestamp()});
    _logActivity(
      groupId: groupId,
      action: ActivityAction.expenseAdded,
      targetName: expense.description,
      amount: expense.amount,
      batch: batch,
    );
    await batch.commit();
  }

  Future<void> updateExpense({
    required String groupId,
    required Expense oldExpense,
    required Expense newExpense,
  }) async {
    final batch = _firestore.batch();
    
    // 1. Update expense doc
    batch.set(_expensesCol(groupId).doc(oldExpense.id), newExpense.toJson());
    batch.update(_groupDoc(groupId), {'updatedAt': FieldValue.serverTimestamp()});
    
    // CALCULATE DELTAS
    final List<String> changes = [];
    if (oldExpense.amount != newExpense.amount) changes.add('amount');
    if (oldExpense.description != newExpense.description) changes.add('description');
    if (oldExpense.payerId != newExpense.payerId) changes.add('payer');
    if (oldExpense.category != newExpense.category) changes.add('category');

    _logActivity(
      groupId: groupId,
      action: ActivityAction.expenseEdited,
      targetName: newExpense.description,
      amount: newExpense.amount,
      metadata: {
        'oldAmount': oldExpense.amount,
        'changes': changes,
      },
      batch: batch,
    );
    await batch.commit();
  }

  Future<void> deleteExpense({
    required String groupId,
    required Expense expense,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_expensesCol(groupId).doc(expense.id));
    batch.update(_groupDoc(groupId), {'updatedAt': FieldValue.serverTimestamp()});
    _logActivity(
      groupId: groupId,
      action: ActivityAction.expenseDeleted,
      targetName: expense.description,
      amount: expense.amount,
      batch: batch,
    );
    await batch.commit();
  }

  // ─── Settlement CRUD ───────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _settlementsCol(String groupId) =>
      _groupDoc(groupId).collection('settlements');

  Stream<List<SettlementRecord>> settlementsStream(String groupId) {
    return _settlementsCol(groupId)
        .snapshots()
        .map((snap) {
          final items = snap.docs.map((doc) => SettlementRecord.fromJson(doc.id, doc.data())).toList();
          items.sort((a, b) => b.settledAt.compareTo(a.settledAt));
          return items;
        });
  }

  Future<void> addSettlement({
    required String groupId,
    required SettlementRecord record,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Settlements always start as 'pending' through the UI flow.
    // They do NOT update balances until confirmed by the receiver.
    final recordData = record.toJson();
    recordData['createdBy'] = user.uid;
    recordData['status'] = SettlementStatus.pending.name;

    await _settlementsCol(groupId).add(recordData);
    await _logActivity(
      groupId: groupId,
      action: ActivityAction.settlementRecorded,
      targetName: "Payment to ${record.toName}",
      amount: record.amount,
    );
    await _groupDoc(groupId).update({'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> confirmSettlement({
    required String groupId,
    required SettlementRecord record,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (record.status == SettlementStatus.confirmed) return;

    final batch = _firestore.batch();
    
    // 1. Mark as confirmed
    batch.update(_settlementsCol(groupId).doc(record.id), {
      'status': SettlementStatus.confirmed.name,
      'confirmedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logActivity(
      groupId: groupId,
      action: ActivityAction.settlementConfirmed,
      targetName: "Payment from ${record.fromName}",
      amount: record.amount,
      batch: batch,
    );
    batch.update(_groupDoc(groupId), {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> disputeSettlement({
    required String groupId,
    required String settlementId,
  }) async {
    final batch = _firestore.batch();
    batch.update(_settlementsCol(groupId).doc(settlementId), {
      'status': SettlementStatus.disputed.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_groupDoc(groupId), {'updatedAt': FieldValue.serverTimestamp()});

    // LOG
    _logActivity(
      groupId: groupId,
      action: ActivityAction.settlementDisputed,
      targetName: "A payment record",
      batch: batch,
    );
    await batch.commit();
  }

  Future<void> deleteSettlement({
    required String groupId,
    required SettlementRecord record,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_settlementsCol(groupId).doc(record.id));
    batch.update(_groupDoc(groupId), {'updatedAt': FieldValue.serverTimestamp()});
    
    // LOG
    _logActivity(
      groupId: groupId,
      action: ActivityAction.expenseDeleted, // Using generic delete or can add settlementDeleted
      targetName: "Payment of ₹${record.amount}",
      batch: batch,
    );

    await batch.commit();
  }

  // ─── Validation ────────────────────────────────────────────────────────

  String? validateUpiId(String? value) {
    if (!isValidUpiId(value ?? '')) return 'Enter a valid UPI ID';
    return null;
  }

  /// Automatically syncs the current user's profile info (Name, UPI ID, Phone)
  /// into the group document if it's missing or outdated.
  Future<void> syncMemberInfo(String groupId, UserProfile profile) async {
    final snap = await _groupDoc(groupId).get();
    final data = snap.data();
    if (data == null) return;

    final membersJson = data['members'] as List<dynamic>? ?? [];
    var members = membersJson.map((m) => GroupMember.fromJson(m as Map<String, dynamic>)).toList();
    
    var changed = false;
    var updatedMembers = <GroupMember>[];

    for (var m in members) {
      // Normalise phone numbers for accurate matching
      final mPhone = (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) ? normalisePhone(m.phoneNumber!) : null;
      final profilePhone = (profile.phoneNumber != null && profile.phoneNumber!.isNotEmpty) ? normalisePhone(profile.phoneNumber!) : null;

      // Find the entry that represents "me" (either by UID or by normalized phone number)
      // CRITICAL: Must not match if both phones are null!
      final isMe = m.id == profile.uid || 
                   (m.uid != null && m.uid == profile.uid) || 
                   (profilePhone != null && mPhone != null && mPhone == profilePhone);
      
      if (isMe) {
        // Does the stored info match our current live profile?
        final nameMatch = m.name == profile.displayName;
        final upiMatch = m.upiId == profile.upiId;
        final phoneMatch = mPhone == profilePhone;
        final uidMatch = m.uid == profile.uid;
        final selfMatch = m.isSelf == true;
        final photoMatch = m.photoUrl == profile.photoUrl;

        // Ensure we actually have a valid UPI ID before claiming everything is fine
        final hasValidUpi = profile.hasUpiId;

        if (!nameMatch || !upiMatch || !phoneMatch || !uidMatch || !selfMatch || !photoMatch || (upiMatch && !hasValidUpi)) {
          updatedMembers.add(m.copyWith(
            uid: profile.uid, 
            name: profile.displayName,
            phoneNumber: profile.phoneNumber,
            upiId: profile.upiId,
            photoUrl: profile.photoUrl,
            isSelf: true,
          ));
          changed = true;
          continue;
        }
      } else if (m.isSelf) {
        // CORRECTION: If this member is NOT me but is marked as self, fix it
        updatedMembers.add(m.copyWith(isSelf: false));
        changed = true;
        continue;
      }
      updatedMembers.add(m);
    }

    if (changed) {
      final memberIds = updatedMembers.map((m) => m.id).toList();
      final memberIdentifiers = <String>{};
      for (final m in updatedMembers) {
        memberIdentifiers.add(m.id);
        if (m.uid != null) memberIdentifiers.add(m.uid!);
        if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
          memberIdentifiers.add(m.phoneNumber!);
        }
      }

      await _groupDoc(groupId).update({
        'members': updatedMembers.map((m) => m.toJson()).toList(),
        'memberIds': memberIds,
        'memberLogins': updatedMembers.where((m) => m.uid != null).map((m) => m.uid!).toList(),
        'memberIdentifiers': memberIdentifiers.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
