import 'dart:async';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
  Map<String, String> _localContactMap = {};

  bool get isSigningIn => _isSigningIn;
  String? get authError => _authError;

  Future<void> loadLocalContacts() async {
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

  String resolveMemberName(GroupMember member) {
    if (member.isSelf) return 'You';
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

  String? _verificationId;
  int? _resendToken;

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
        _resendToken = token;
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
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  Future<void> _ensureUserProfile(User? user) async {
    if (user == null) return;

    final doc = _userDoc(user.uid);
    final snapshot = await doc.get();

    final normalizedEmail = (user.email ?? '').toLowerCase();
    
    // Check if another user already claimed this email
    if (normalizedEmail.isNotEmpty) {
       final existing = await lookupUserByContact(normalizedEmail);
       if (existing != null && existing.uid != user.uid) {
          // This email is already taken.
       }
    }

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

    final normalizedPhone = phoneNumber != null ? normalisePhone(phoneNumber) : null;

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
    });
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
  Stream<List<SettlementGroup>> groupsStream({required String uid, String? phoneNumber}) {
    final identifiers = [uid];
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      identifiers.add(phoneNumber);
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

    // Collect all member UIDs and phone numbers for global lookup.
    final memberIds = normalizedMembers.map((m) => m.id).toList();
    final memberIdentifiers = <String>{};
    for (final m in normalizedMembers) {
      memberIdentifiers.add(m.id);
      if (m.id.startsWith('manual_') || m.id.startsWith('contact_')) {
         // If it's a guest, they only have an opaque ID or phone.
      }
      if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
        memberIdentifiers.add(m.phoneNumber!);
      }
    }

    await _groupsCol.add({
      'name': name.trim(),
      'createdBy': user.uid,
      'isNonGroup': isNonGroup,
      'memberIds': memberIds,
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
      if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
        memberIdentifiers.add(m.phoneNumber!);
      }
    }

    final Map<String, dynamic> data = {
      'members': normalized.map((m) => m.toJson()).toList(),
      'memberIds': memberIds,
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
    
    // Update aggregated balances
    final Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final Map<String, int> netDeltas = {};
    // Payer Impact
    netDeltas[expense.payerId] = (netDeltas[expense.payerId] ?? 0) + expense.amount;
    // Shares Impact
    for (var entry in expense.shares.entries) {
      netDeltas[entry.key] = (netDeltas[entry.key] ?? 0) - entry.value;
    }

    for (var entry in netDeltas.entries) {
      if (entry.value != 0) {
        updates['netBalances.${entry.key}'] = FieldValue.increment(entry.value);
      }
    }
    batch.update(_groupDoc(groupId), updates);
    
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
    
    // 2. Adjust aggregated balances
    final Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // The most reliable way is to sum all local deltas per member first.
    final Map<String, int> netDeltas = {};
    
    // Payer Impact
    netDeltas[oldExpense.payerId] = (netDeltas[oldExpense.payerId] ?? 0) - oldExpense.amount;
    netDeltas[newExpense.payerId] = (netDeltas[newExpense.payerId] ?? 0) + newExpense.amount;
    
    // Shares Impact
    for (var entry in oldExpense.shares.entries) {
      netDeltas[entry.key] = (netDeltas[entry.key] ?? 0) + entry.value;
    }
    for (var entry in newExpense.shares.entries) {
      netDeltas[entry.key] = (netDeltas[entry.key] ?? 0) - entry.value;
    }

    for (var entry in netDeltas.entries) {
      if (entry.value != 0) {
        updates['netBalances.${entry.key}'] = FieldValue.increment(entry.value);
      }
    }

    batch.update(_groupDoc(groupId), updates);
    await batch.commit();
  }

  Future<void> deleteExpense({
    required String groupId,
    required Expense expense,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_expensesCol(groupId).doc(expense.id));
    
    // Revert aggregated balances
    final Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
    };
    
    final Map<String, int> netDeltas = {};
    // Revert Payer Impact
    netDeltas[expense.payerId] = (netDeltas[expense.payerId] ?? 0) - expense.amount;
    // Revert Shares Impact
    for (var entry in expense.shares.entries) {
      netDeltas[entry.key] = (netDeltas[entry.key] ?? 0) + entry.value;
    }

    for (var entry in netDeltas.entries) {
      if (entry.value != 0) {
        updates['netBalances.${entry.key}'] = FieldValue.increment(entry.value);
      }
    }
    batch.update(_groupDoc(groupId), updates);
    
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
    
    // Touch group for activity feed
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
    });
    
    // 2. Update aggregated balances: payer (from) up, payee (to) down
    batch.update(_groupDoc(groupId), {
      'updatedAt': FieldValue.serverTimestamp(),
      'netBalances.${record.fromMemberId}': FieldValue.increment(record.amount),
      'netBalances.${record.toMemberId}': FieldValue.increment(-record.amount),
    });
    
    await batch.commit();
  }

  Future<void> disputeSettlement({
    required String groupId,
    required String settlementId,
  }) async {
    await _settlementsCol(groupId).doc(settlementId).update({
      'status': SettlementStatus.disputed.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteSettlement({
    required String groupId,
    required SettlementRecord record,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_settlementsCol(groupId).doc(record.id));
    
    // Only revert aggregated balances if it was previously confirmed
    if (record.status == SettlementStatus.confirmed) {
      batch.update(_groupDoc(groupId), {
        'updatedAt': FieldValue.serverTimestamp(),
        'netBalances.${record.fromMemberId}': FieldValue.increment(-record.amount),
        'netBalances.${record.toMemberId}': FieldValue.increment(record.amount),
      });
    }
    
    await batch.commit();
  }

  // ─── Validation ────────────────────────────────────────────────────────

  String? validateUpiId(String? value) {
    if (!isValidUpiId(value ?? '')) return 'Enter a valid UPI ID';
    return null;
  }
}
