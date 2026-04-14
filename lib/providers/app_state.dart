import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/expense.dart';
import '../models/group_member.dart';
import '../models/settlement_group.dart';
import '../models/settlement_record.dart';
import '../models/user_profile.dart';
import '../utils/upi_helper.dart';

class AppState extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _initializingGoogle = false;
  bool _isSigningIn = false;
  String? _authError;

  bool get isSigningIn => _isSigningIn;
  String? get authError => _authError;
  FirebaseAuth get auth => _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> _initializeGoogleSignIn() async {
    if (_initializingGoogle) return;
    _initializingGoogle = true;
    await GoogleSignIn.instance.initialize();
  }

  Future<void> signInWithGoogle() async {
    _authError = null;
    _isSigningIn = true;
    notifyListeners();

    try {
      await _initializeGoogleSignIn();
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      await _ensureUserProfile(userCredential.user);
    } on FirebaseAuthException catch (error) {
      _authError = error.message ?? error.code;
    } on GoogleSignInException catch (error) {
      _authError = error.description ?? error.code.toString();
    } catch (error) {
      _authError = error.toString();
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  Future<void> _ensureUserProfile(User? user) async {
    if (user == null) return;

    final doc = _userDoc(user.uid);
    final snapshot = await doc.get();
    if (snapshot.exists) {
      await doc.set(
        {
          'displayName': user.displayName ?? 'User',
          'email': user.email ?? '',
          'photoUrl': user.photoURL,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return;
    }

    await doc.set({
      'displayName': user.displayName ?? 'User',
      'email': (user.email ?? '').toLowerCase(),
      'photoUrl': user.photoURL,
      'phoneNumber': user.phoneNumber ?? '',
      'upiId': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  Stream<Map<String, UserProfile>> profilesStream(List<String> uids) {
    if (uids.isEmpty) return Stream.value({});
    // Firestore IN query limit is 30, but group members are usually < 10.
    final chunks = <List<String>>[];
    for (var i = 0; i < uids.length; i += 10) {
      chunks.add(uids.sublist(i, i + 10 > uids.length ? uids.length : i + 10));
    }

    // For simplicity, we listen to the 'users' collection where doc ID is in uids.
    // Note: 'whereField(FieldPath.documentId(), whereIn: ...)'
    return _firestore.collection('users')
        .where(FieldPath.documentId, whereIn: uids.take(30).toList())
        .snapshots()
        .map((snap) {
          final map = <String, UserProfile>{};
          for (final doc in snap.docs) {
            map[doc.id] = UserProfile.fromJson(doc.id, doc.data());
          }
          return map;
        });
  }

  Future<void> saveProfile({String? upiId, String? phoneNumber}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (upiId != null) updates['upiId'] = upiId.trim();
    if (phoneNumber != null) updates['phoneNumber'] = normalisePhone(phoneNumber);

    await _userDoc(user.uid).set(updates, SetOptions(merge: true));
  }

  Future<void> saveUpiId(String upiId) => saveProfile(upiId: upiId);

  // ─── Contact lookup ──────────────────────────────────────────────────────

  Future<UserProfile?> lookupUserByContact(String contact) async {
    final queryText = contact.trim();
    if (queryText.isEmpty) return null;

    final isEmail = queryText.contains('@');
    final queryField = isEmail ? 'email' : 'phoneNumber';
    final queryValue = isEmail ? queryText.toLowerCase() : normalisePhone(queryText);

    if (queryValue.isEmpty) return null;

    final snapshot = await _firestore
        .collection('users')
        .where(queryField, isEqualTo: queryValue)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return UserProfile.fromJson(doc.id, doc.data());
  }

  static String normalisePhone(String raw) {
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
    // Final check: if it doesn't start with +, prepend it (safeguard)
    else if (!cleaned.startsWith('+')) {
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
  Stream<List<SettlementGroup>> groupsStream(String uid) {
    return _groupsCol
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final items = snap.docs
          .map((doc) => SettlementGroup.fromJson(doc.id, doc.data()))
          .where((g) {
            // Soft delete check
            final data = snap.docs.firstWhere((d) => d.id == g.id).data();
            return data['isDeleted'] != true;
          })
          .toList();
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    });
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

    // Collect all member UIDs for the memberIds index.
    // For guests (no uid), we generate a stable opaque id stored in member.id.
    final memberIds = normalizedMembers.map((m) => m.id).toList();

    await _groupsCol.add({
      'name': name.trim(),
      'createdBy': user.uid,
      'isNonGroup': isNonGroup,
      'memberIds': memberIds,
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
  }

  Future<void> updateGroupMembers({
    required String groupId,
    required List<GroupMember> members,
  }) async {
    final normalized = members.map((m) => GroupMember(
      id: m.id,
      name: m.name,
      phoneNumber: m.phoneNumber != null ? normalisePhone(m.phoneNumber!) : null,
      upiId: m.upiId,
    )).toList();
    final memberIds = normalized.map((m) => m.id).toList();
    await _groupDoc(groupId).set(
      {
        'members': normalized.map((m) => m.toJson()).toList(),
        'memberIds': memberIds,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
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
    await _expensesCol(groupId).add(expense.toJson());
    // Touch the group's updatedAt so members' group-list streams see activity.
    await _groupDoc(groupId).set(
      {'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteExpense({
    required String groupId,
    required String expenseId,
  }) async {
    await _expensesCol(groupId).doc(expenseId).delete();
    await _groupDoc(groupId).set(
      {'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
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
    await _settlementsCol(groupId).add(record.toJson());
    await _groupDoc(groupId).set(
      {'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteSettlement({
    required String groupId,
    required String settlementId,
  }) async {
    await _settlementsCol(groupId).doc(settlementId).delete();
    await _groupDoc(groupId).set(
      {'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  // ─── Validation ────────────────────────────────────────────────────────

  String? validateUpiId(String? value) {
    if (!isValidUpiId(value ?? '')) return 'Enter a valid UPI ID';
    return null;
  }
}
