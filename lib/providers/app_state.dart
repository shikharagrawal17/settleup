import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/expense.dart';
import '../models/group_member.dart';
import '../models/settlement_group.dart';
import '../models/settlement_record.dart';
import '../models/user_profile.dart';
import '../models/activity_log.dart';
import '../utils/settlement_helper.dart';
import '../utils/upi_helper.dart';

class AppState extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isSigningIn = false;
  bool _hasAttemptedSilentSignIn = false;
  String? _authError;
  Map<String, String> _localContactMap = {};
  String? _pendingJoinGroupId;

  String? get pendingJoinGroupId => _pendingJoinGroupId;
  set pendingJoinGroupId(String? val) {
    _pendingJoinGroupId = val;
    notifyListeners();
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn();
  StreamSubscription<User?>? _userSub;

  AppState() {
    _initAuth();
  }

  void _initAuth() {
    _userSub = _auth.authStateChanges().listen((user) async {
       if (user != null) {
         _ensureUserProfile(user);
         _initMessaging();
       } else if (kIsWeb && !_hasAttemptedSilentSignIn) {
         _hasAttemptedSilentSignIn = true;
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

  Future<void> _initMessaging() async {
    if (kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await messaging.getToken();
        if (token != null) {
          final user = _auth.currentUser;
          if (user != null) {
            await _firestore.collection('registries').doc(user.uid).set({
              'fcmToken': token,
              'lastTokenUpdate': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }
    } catch (e) {
      debugPrint('Error initializing messaging: $e');
    }
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

  String resolveMemberName(GroupMember member) {
    // Only return 'You' if the ID actually matches the current user's UID 
    // or if it's explicitly marked as self AND it's truly the current user.
    final currentUid = _auth.currentUser?.uid;
    if (member.id == currentUid || (member.uid != null && member.uid == currentUid)) {
      return 'You';
    }
    
    // Check if we have a local contact name for this person
    if (member.phoneNumber != null) {
      final normalised = AppState.normalisePhone(member.phoneNumber!);
      if (_localContactMap.containsKey(normalised)) {
        return _localContactMap[normalised]!;
      }
    }

    // Default to the stored name in the member object
    return member.name;
  }

  /// Automatically syncs all group members' info (Name, UPI ID, Phone, Photo)
  /// into the group document. Renamed from syncMemberInfo for expanded scope.
  /// Deduplicates members with same phone/UID and migrates expenses if needed.
  Future<void> syncGroupMembers(String groupId, UserProfile myProfile) async {
    final snap = await _groupDoc(groupId).get();
    final data = snap.data();
    if (data == null) return;

    final originalMembers = (data['members'] as List<dynamic>? ?? [])
        .map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
        .toList();

    // 1. One-off fetch for profiles involved (for real-time consistency)
    final profileMap = <String, UserProfile>{};
    profileMap[myProfile.uid] = myProfile; // Save me!

    // Collect all phone numbers to look up
    final allPhones = originalMembers
        .where((m) => m.phoneNumber != null && m.phoneNumber!.isNotEmpty)
        .map((m) => normalisePhone(m.phoneNumber!))
        .toSet();

    for (final phone in allPhones) {
      final p = await lookupUserByContact(phone);
      if (p != null) {
        profileMap[p.uid] = p;
        profileMap[phone] = p;
      }
    }

    // 2. Build the new member list and merge map
    final updatedMembers = <GroupMember>[];
    final memberMergeMap = <String, String>{}; // oldId -> survivingId
    final seenPeople = <String, String>{}; // Identity (UID or Phone) -> survivingId
    var changed = false;

    for (final m in originalMembers) {
      final mPhone = m.phoneNumber != null ? normalisePhone(m.phoneNumber!) : null;
      final profile = profileMap[m.uid] ?? (mPhone != null ? profileMap[mPhone] : null);
      
      // Effective identifier for deduplication
      final personId = profile?.uid ?? mPhone ?? m.id;

      if (seenPeople.containsKey(personId)) {
        // DUPLICATE DETECTED! Merge this ID into the already seen one.
        memberMergeMap[m.id] = seenPeople[personId]!;
        changed = true;
        continue;
      }

      // Sync data from profile if found
      var updated = m;
      if (profile != null) {
        updated = m.copyWith(
          uid: profile.uid,
          name: profile.displayName,
          phoneNumber: profile.phoneNumber,
          upiId: profile.upiId,
          photoUrl: profile.photoUrl,
          isSelf: profile.uid == myProfile.uid,
        );
      } else if (m.uid == myProfile.uid) {
        updated = m.copyWith(isSelf: true);
      } else if (m.isSelf && m.uid != myProfile.uid) {
        updated = m.copyWith(isSelf: false);
      }

      if (updated.toJson().toString() != m.toJson().toString()) {
        changed = true;
      }

      updatedMembers.add(updated);
      seenPeople[personId] = updated.id;
    }

    // 3. Persist changes
    if (changed) {
      // If we merged IDs, we MUST migrate expenses and settlements first
      if (memberMergeMap.isNotEmpty) {
        await _migrateGroupData(groupId, memberMergeMap);
      }

      final memberIds = updatedMembers.map((m) => m.id).toList();
      final memberIdentifiers = <String>{};
      for (final m in updatedMembers) {
        memberIdentifiers.add(m.id);
        if (m.uid != null) memberIdentifiers.add(m.uid!);
        if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
          memberIdentifiers.add(normalisePhone(m.phoneNumber!));
        }
      }

      final Map<String, dynamic> groupUpdates = {
        'members': updatedMembers.map((m) => m.toJson()).toList(),
        'memberIds': memberIds,
        'memberLogins': updatedMembers.where((m) => m.uid != null).map((m) => m.uid!).toList(),
        'memberIdentifiers': memberIdentifiers.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (memberMergeMap.isNotEmpty) {
        final balancesRaw = data['netBalances'] as Map<String, dynamic>? ?? {};
        if (balancesRaw.isNotEmpty) {
          final newBalances = <String, double>{};
          balancesRaw.forEach((key, val) {
            final targetKey = memberMergeMap[key] ?? key;
            newBalances[targetKey] = (newBalances[targetKey] ?? 0.0) + (val as num).toDouble();
          });
          for (final oldKey in memberMergeMap.keys) {
            groupUpdates['netBalances.$oldKey'] = FieldValue.delete();
          }
          for (final entry in newBalances.entries) {
            groupUpdates['netBalances.${entry.key}'] = entry.value;
          }
        }
      }

      await _groupDoc(groupId).update(groupUpdates);
    }
  }

  /// Helper to migrate group accounting data when members are merged.
  Future<void> _migrateGroupData(String groupId, Map<String, String> mergeMap) async {
    WriteBatch currentBatch = _firestore.batch();
    int opCount = 0;

    Future<void> commitBatchIfNeeded() async {
      opCount++;
      if (opCount >= 400) {
        await currentBatch.commit();
        currentBatch = _firestore.batch();
        opCount = 0;
      }
    }
    
    // 1. Update Expenses
    final expSnap = await _expensesCol(groupId).get();
    for (final doc in expSnap.docs) {
      final data = doc.data();
      var changed = false;

      // Update Payer
      final payerId = data['payerId'] as String?;
      if (payerId != null && mergeMap.containsKey(payerId)) {
        data['payerId'] = mergeMap[payerId];
        changed = true;
      }

      // Update Shares (Merge amounts if multiple IDs point to same person)
      final shares = Map<String, dynamic>.from(data['shares'] as Map? ?? {});
      final newShares = <String, dynamic>{};
      var sharesModified = false;
      
      shares.forEach((id, amount) {
        final targetId = mergeMap[id] ?? id;
        if (targetId != id) sharesModified = true;
        newShares[targetId] = (newShares[targetId] ?? 0.0) + (amount as num).toDouble();
      });

      if (sharesModified) {
        data['shares'] = newShares;
        changed = true;
      }

      if (changed) {
        currentBatch.update(doc.reference, data);
        await commitBatchIfNeeded();
      }
    }

    // 2. Update Settlements
    final setSnap = await _settlementsCol(groupId).get();
    for (final doc in setSnap.docs) {
      final data = doc.data();
      var changed = false;

      final fromId = data['fromMemberId'] as String?;
      if (fromId != null && mergeMap.containsKey(fromId)) {
        data['fromMemberId'] = mergeMap[fromId];
        changed = true;
      }

      final toId = data['toMemberId'] as String?;
      if (toId != null && mergeMap.containsKey(toId)) {
        data['toMemberId'] = mergeMap[toId];
        changed = true;
      }

      if (changed) {
        currentBatch.update(doc.reference, data);
        await commitBatchIfNeeded();
      }
    }

    if (opCount > 0) {
      await currentBatch.commit();
    }
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
    final normPhone = phoneNumber != null ? normalisePhone(phoneNumber) : null;
    await _userDoc(uid).set({
      'displayName': displayName,
      'phoneNumber': normPhone,
      'upiId': upiId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _publicUserDoc(uid).set({
      'displayName': displayName,
      'phoneNumber': normPhone,
      'upiId': upiId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (normPhone != null && normPhone.isNotEmpty) {
      await _upsertRegistry(key: 'phone_$normPhone', uid: uid);
    }
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

  Stream<List<SettlementGroup>> groupsStream({required String uid, String? phoneNumber}) {
    final identifiers = <String>[uid];
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      identifiers.add(normalisePhone(phoneNumber));
    }
    
    return _firestore.collection('groups')
        .where('memberIdentifiers', arrayContainsAny: identifiers)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) {
                try {
                  return SettlementGroup.fromJson(doc.id, doc.data());
                } catch (e) {
                  return null;
                }
              })
              .whereType<SettlementGroup>()
              .where((g) => !g.isDeleted)
              .toList();
          
          items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return items;
        });
  }

  /// All groups where the current user is a member, including deleted ones.
  Stream<List<SettlementGroup>> groupsWithDeletedStream({required String uid, String? phoneNumber}) {
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
          .toList();
      items.sort((a, b) {
        final dateA = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
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
      photoUrl: profile.photoUrl,
      uid: user.uid,
      isSelf: true,
    );

    final normalizedMembers = <GroupMember>[
      selfMember,
      ...members.where((m) => m.id != user.uid).map((m) => GroupMember(
        id: m.id,
        name: m.name,
        phoneNumber: m.phoneNumber != null ? normalisePhone(m.phoneNumber!) : null,
        upiId: m.upiId,
        uid: m.uid,
        photoUrl: m.photoUrl,
        isSelf: m.isSelf,
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
        memberIdentifiers.add(normalisePhone(m.phoneNumber!));
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
      'lastActionBy': profile.displayName,
      'lastActionType': 'created',
    });
  }

  Future<void> deleteGroup(String groupId, String actorName) async {
    await _groupDoc(groupId).set(
      {
        'isDeleted': true, 
        'updatedAt': FieldValue.serverTimestamp(),
        'lastActionBy': actorName,
        'lastActionType': 'deleted',
      },
      SetOptions(merge: true),
    );
  }

  Future<void> restoreGroup(String groupId, String actorName) async {
    await _groupDoc(groupId).set(
      {
        'isDeleted': false, 
        'updatedAt': FieldValue.serverTimestamp(),
        'lastActionBy': actorName,
        'lastActionType': 'restored',
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updateGroup({
    required String groupId,
    required Map<String, dynamic> updates,
  }) async {
    await _groupDoc(groupId).update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGroupName({
    required String groupId,
    required String name,
  }) async {
    await updateGroup(groupId: groupId, updates: {'name': name.trim()});
    await _logActivity(
      groupId: groupId,
      action: ActivityAction.groupEdited,
      targetName: name.trim(),
    );
  }

  Future<void> joinGroup(String groupId, UserProfile profile) async {
    final doc = await _groupDoc(groupId).get();
    if (!doc.exists) throw Exception('Group not found');
    
    final data = doc.data() as Map<String, dynamic>;
    final List membersRaw = data['members'] ?? [];
    final members = membersRaw.map((m) => GroupMember.fromJson(m)).toList();
    
    // Check if already in
    final normProfilePhone = (profile.phoneNumber != null && profile.phoneNumber!.isNotEmpty)
        ? normalisePhone(profile.phoneNumber!)
        : null;
    if (members.any((m) {
      if (m.uid == profile.uid || m.id == profile.uid) return true;
      if (normProfilePhone != null && m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
        return normalisePhone(m.phoneNumber!) == normProfilePhone;
      }
      return false;
    })) {
       syncGroupMembers(groupId, profile);
       return; // Already in
    }

    // Add as new member
    final newMember = GroupMember(
      id: profile.uid,
      name: profile.displayName,
      uid: profile.uid,
      phoneNumber: profile.phoneNumber,
      upiId: profile.upiId,
      photoUrl: profile.photoUrl,
    );
    
    final phone = newMember.phoneNumber != null ? normalisePhone(newMember.phoneNumber!) : null;
    final identifiers = [newMember.id, newMember.uid!];
    if (phone != null && phone.isNotEmpty) identifiers.add(phone);

    await _groupDoc(groupId).update({
      'members': FieldValue.arrayUnion([newMember.toJson()]),
      'memberIds': FieldValue.arrayUnion([newMember.id]),
      'memberLogins': FieldValue.arrayUnion([newMember.uid!]),
      'memberIdentifiers': FieldValue.arrayUnion(identifiers),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Fire and forget deduplication sync
    syncGroupMembers(groupId, profile);

    await _logActivity(
      groupId: groupId,
      action: ActivityAction.memberAdded,
      targetName: profile.displayName,
    );
  }

  Future<void> updateGroupMembers({
    required String groupId,
    required List<GroupMember> members,
    String? newCreatorId,
  }) async {
    final docSnap = await _groupDoc(groupId).get();
    if (docSnap.exists) {
      final data = docSnap.data() as Map<String, dynamic>;
      final group = SettlementGroup.fromJson(groupId, data);
      final currentMembers = group.members;
      final newMemberIdsSet = members.map((m) => m.id).toSet();
      
      final removedMembers = currentMembers.where((m) => !newMemberIdsSet.contains(m.id)).toList();
      if (removedMembers.isNotEmpty) {
        Map<String, double> balances = group.netBalances;
        
        // Fallback for unmigrated groups
        if (balances.isEmpty) {
          final expensesSnap = await _expensesCol(groupId).get();
          final settlementsSnap = await _settlementsCol(groupId).get();
          
          final expenses = expensesSnap.docs.map((d) => Expense.fromJson(d.id, d.data())).toList();
          final settlements = settlementsSnap.docs.map((d) => SettlementRecord.fromJson(d.id, d.data())).toList();
          
          balances = computeMemberBalances(members: currentMembers, expenses: expenses, settlements: settlements);
        }
        
        for (final rm in removedMembers) {
          if ((balances[rm.id] ?? 0.0).abs() >= 0.01) {
            throw Exception('Cannot remove member ${rm.name} because their balance is not settled.');
          }
        }
      }
    }
    final normalized = members.map((m) => GroupMember(
      id: m.id,
      name: m.name,
      phoneNumber: m.phoneNumber != null ? normalisePhone(m.phoneNumber!) : null,
      upiId: m.upiId,
      uid: m.uid,
      photoUrl: m.photoUrl,
      isSelf: m.isSelf,
    )).toList();

    final memberIds = normalized.map((m) => m.id).toList();
    final memberIdentifiers = <String>{};
    for (final m in normalized) {
      memberIdentifiers.add(m.id);
      if (m.uid != null) memberIdentifiers.add(m.uid!);
      if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
        memberIdentifiers.add(normalisePhone(m.phoneNumber!));
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

    // Sync group members to refresh info and deduplicate
    final authUid = _auth.currentUser?.uid;
    if (authUid != null) {
      final pSnap = await _publicUserDoc(authUid).get();
      if (pSnap.exists) {
        final profile = UserProfile.fromJson(authUid, pSnap.data()!);
        syncGroupMembers(groupId, profile); // Fire and forget
      }
    }
  }

  // ─── Expense CRUD ──────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _expensesCol(String groupId) =>
      _groupDoc(groupId).collection('expenses');

  Stream<List<Expense>> expensesStream(String groupId) {
    return _expensesCol(groupId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          final items = snap.docs.map((doc) => Expense.fromJson(doc.id, doc.data())).toList();
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
    
    // Calculate and apply netBalance deltas (using base currency if available)
    final scale = (expense.baseAmount != null && expense.amount > 0) 
        ? (expense.baseAmount! / expense.amount) 
        : 1.0;
    final effectiveTotal = expense.baseAmount ?? expense.amount;

    final deltas = <String, double>{};
    deltas[expense.payerId] = effectiveTotal;
    expense.shares.forEach((memberId, shareAmount) {
      deltas[memberId] = (deltas[memberId] ?? 0.0) - (shareAmount * scale);
    });

    final groupUpdates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'totalSpent': FieldValue.increment(effectiveTotal),
    };
    for (final entry in deltas.entries) {
      if (entry.value.abs() > 0.001) {
        groupUpdates['netBalances.${entry.key}'] = FieldValue.increment(entry.value);
      }
    }
    batch.update(_groupDoc(groupId), groupUpdates);
    _logActivity(
      groupId: groupId,
      action: ActivityAction.expenseAdded,
      targetName: expense.description,
      amount: expense.amount,
      batch: batch,
    );
    await batch.commit();

    // Sync group members to refresh info and deduplicate
    final profileSnap = await _publicUserDoc(user.uid).get();
    if (profileSnap.exists) {
      final profile = UserProfile.fromJson(user.uid, profileSnap.data()!);
      syncGroupMembers(groupId, profile); // Fire and forget
    }
    notifyListeners();
  }

  Future<void> updateExpense({
    required String groupId,
    required Expense oldExpense,
    required Expense newExpense,
  }) async {
    final batch = _firestore.batch();
    
    // 1. Update expense doc
    batch.set(_expensesCol(groupId).doc(oldExpense.id), newExpense.toJson());
    
    // 2. Update netBalances
    final oldScale = (oldExpense.baseAmount != null && oldExpense.amount > 0) ? (oldExpense.baseAmount! / oldExpense.amount) : 1.0;
    final oldEffective = oldExpense.baseAmount ?? oldExpense.amount;
    
    final newScale = (newExpense.baseAmount != null && newExpense.amount > 0) ? (newExpense.baseAmount! / newExpense.amount) : 1.0;
    final newEffective = newExpense.baseAmount ?? newExpense.amount;

    final deltas = <String, double>{};
    // Revert old
    deltas[oldExpense.payerId] = -oldEffective;
    oldExpense.shares.forEach((memberId, shareAmount) {
      deltas[memberId] = (deltas[memberId] ?? 0.0) + (shareAmount * oldScale);
    });
    // Add new
    deltas[newExpense.payerId] = (deltas[newExpense.payerId] ?? 0.0) + newEffective;
    newExpense.shares.forEach((memberId, shareAmount) {
      deltas[memberId] = (deltas[memberId] ?? 0.0) - (shareAmount * newScale);
    });

    final groupUpdates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'totalSpent': FieldValue.increment(newEffective - oldEffective),
    };
    for (final entry in deltas.entries) {
      if (entry.value != 0) {
        groupUpdates['netBalances.${entry.key}'] = FieldValue.increment(entry.value);
      }
    }
    batch.update(_groupDoc(groupId), groupUpdates);
    
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
    
    // Calculate scale and effective total for reversal
    final scale = (expense.baseAmount != null && expense.amount > 0) 
        ? (expense.baseAmount! / expense.amount) 
        : 1.0;
    final effectiveTotal = expense.baseAmount ?? expense.amount;

    final deltas = <String, double>{};
    deltas[expense.payerId] = -effectiveTotal;
    expense.shares.forEach((memberId, shareAmount) {
      deltas[memberId] = (deltas[memberId] ?? 0.0) + (shareAmount * scale);
    });

    final groupUpdates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'totalSpent': FieldValue.increment(-effectiveTotal),
    };
    for (final entry in deltas.entries) {
      if (entry.value.abs() > 0.001) {
        groupUpdates['netBalances.${entry.key}'] = FieldValue.increment(entry.value);
      }
    }
    batch.update(_groupDoc(groupId), groupUpdates);
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
    bool confirmed = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final recordData = record.toJson();
    recordData['createdBy'] = user.uid;
    recordData['status'] = confirmed ? SettlementStatus.confirmed.name : SettlementStatus.pending.name;

    final batch = _firestore.batch();
    final docRef = _settlementsCol(groupId).doc();
    batch.set(docRef, recordData);

    final groupUpdates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (confirmed) {
      groupUpdates['netBalances.${record.fromMemberId}'] = FieldValue.increment(record.amount);
      groupUpdates['netBalances.${record.toMemberId}'] = FieldValue.increment(-record.amount);
    }
    batch.update(_groupDoc(groupId), groupUpdates);

    await _logActivity(
      groupId: groupId,
      action: confirmed ? ActivityAction.settlementConfirmed : ActivityAction.settlementRecorded,
      targetName: "Payment to ${record.toName}",
      amount: record.amount,
      metadata: {
        'settlementId': docRef.id,
        'fromMemberId': record.fromMemberId,
        'toMemberId': record.toMemberId,
      },
      batch: batch,
    );
    
    await batch.commit();

    // Sync group members to refresh info and deduplicate
    final profileSnap = await _publicUserDoc(user.uid).get();
    if (profileSnap.exists) {
      final profile = UserProfile.fromJson(user.uid, profileSnap.data()!);
      syncGroupMembers(groupId, profile); // Fire and forget
    }
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

    final groupUpdates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    groupUpdates['netBalances.${record.fromMemberId}'] = FieldValue.increment(record.amount);
    groupUpdates['netBalances.${record.toMemberId}'] = FieldValue.increment(-record.amount);
    batch.update(_groupDoc(groupId), groupUpdates);

    _logActivity(
      groupId: groupId,
      action: ActivityAction.settlementConfirmed,
      targetName: "Payment from ${record.fromName}",
      amount: record.amount,
      batch: batch,
    );
    await batch.commit();

    // Sync group members to refresh info and deduplicate
    final profileSnap = await _publicUserDoc(user.uid).get();
    if (profileSnap.exists) {
      final profile = UserProfile.fromJson(user.uid, profileSnap.data()!);
      syncGroupMembers(groupId, profile); // Fire and forget
    }
  }

  Future<void> disputeSettlement({
    required String groupId,
    required SettlementRecord record,
  }) async {
    final batch = _firestore.batch();
    batch.update(_settlementsCol(groupId).doc(record.id), {
      'status': SettlementStatus.disputed.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final groupUpdates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    // If the settlement was already confirmed, reversing it requires adjusting netBalances!
    if (record.status == SettlementStatus.confirmed) {
      groupUpdates['netBalances.${record.fromMemberId}'] = FieldValue.increment(-record.amount);
      groupUpdates['netBalances.${record.toMemberId}'] = FieldValue.increment(record.amount);
    }
    batch.update(_groupDoc(groupId), groupUpdates);

    // LOG
    _logActivity(
      groupId: groupId,
      action: ActivityAction.settlementDisputed,
      targetName: "Payment from ${record.fromName}",
      amount: record.amount,
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
    
    final groupUpdates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (record.status == SettlementStatus.confirmed) {
      groupUpdates['netBalances.${record.fromMemberId}'] = FieldValue.increment(-record.amount);
      groupUpdates['netBalances.${record.toMemberId}'] = FieldValue.increment(record.amount);
    }
    batch.update(_groupDoc(groupId), groupUpdates);
    
    // LOG
    _logActivity(
      groupId: groupId,
      action: ActivityAction.settlementDeleted,
      targetName: "Payment from ${record.fromName}",
      batch: batch,
      amount: record.amount,
    );

    await batch.commit();
  }

  // ─── Migration ─────────────────────────────────────────────────────────

  Future<void> migrateGroupBalances(String groupId, Map<String, double> balances, double totalSpent) async {
    final updates = <String, dynamic>{
      'totalSpent': totalSpent,
    };
    for (final entry in balances.entries) {
      updates['netBalances.${entry.key}'] = entry.value;
    }
    await _groupDoc(groupId).update(updates);
  }

  // ─── Validation ────────────────────────────────────────────────────────

  String? validateUpiId(String? value) {
    if (!isValidUpiId(value ?? '')) return 'Enter a valid UPI ID';
    return null;
  }

  /// Automatically syncs the current user's profile info (Name, UPI ID, Phone)
  /// into the group document if it's missing or outdated.

}
