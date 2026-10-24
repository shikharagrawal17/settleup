import 'package:flutter_test/flutter_test.dart';
import 'package:bharat_dues/models/group_member.dart';
import 'package:bharat_dues/models/expense.dart';
import 'package:bharat_dues/models/settlement_record.dart';
import 'package:bharat_dues/utils/settlement_helper.dart';

void main() {
  group('Financial Audit & Double-Entry Ledger Invariants', () {
    test('User Reported Scenario: Update Expense from Other to Me with Pending Settlement', () {
      final members = [
        GroupMember(id: 'member_user_a', uid: 'firebase_uid_a', name: 'User A', phoneNumber: '+919876543210'),
        GroupMember(id: 'manual_user_b', name: 'User B', phoneNumber: '+919999988888'),
      ];

      // Initial state: Expense 1: 3000 paid by User B, split 2 ways
      final expense1 = Expense(
        id: 'exp_1',
        description: 'Dinner',
        amount: 3000.0,
        payerId: 'manual_user_b',
        shares: {
          'firebase_uid_a': 1500.0, // Used UID instead of member.id
          'manual_user_b': 1500.0,
        },
        createdAt: DateTime.now(),
        createdBy: 'manual_user_b',
      );

      final initialBalances = computeMemberBalances(
        members: members,
        expenses: [expense1],
        settlements: [],
      );

      // User A owes 1500, User B is owed 1500
      expect(initialBalances['member_user_a'], equals(-1500.0));
      expect(initialBalances['manual_user_b'], equals(1500.0));
      expect(initialBalances['member_user_a']! + initialBalances['manual_user_b']!, equals(0.0));

      // User A records payment of 1400 (Pending confirmation from User B)
      final pendingSettlement = SettlementRecord(
        id: 'set_1',
        fromMemberId: 'firebase_uid_a',
        fromName: 'User A',
        toMemberId: 'manual_user_b',
        toName: 'User B',
        amount: 1400.0,
        settledAt: DateTime.now(),
        status: SettlementStatus.pending,
        createdBy: 'firebase_uid_a',
      );

      // Pending settlement must NOT corrupt confirmed ledger balances
      final balancesWithPending = computeMemberBalances(
        members: members,
        expenses: [expense1],
        settlements: [pendingSettlement],
      );
      expect(balancesWithPending['member_user_a'], equals(-1500.0));
      expect(balancesWithPending['manual_user_b'], equals(1500.0));

      // Now Transaction 1 is updated: "Paid by User B" -> "Paid by User A (Me)"
      final updatedExpense1 = Expense(
        id: 'exp_1',
        description: 'Dinner',
        amount: 3000.0,
        payerId: 'firebase_uid_a', // Updated to User A
        shares: {
          'member_user_a': 1500.0,
          'manual_user_b': 1500.0,
        },
        createdAt: DateTime.now(),
        createdBy: 'firebase_uid_a',
      );

      final balancesAfterUpdate = computeMemberBalances(
        members: members,
        expenses: [updatedExpense1],
        settlements: [pendingSettlement],
      );

      // AUDIT CHECK: User A is owed 1500 (to be received), User B owes 1500 (to be paid)
      expect(balancesAfterUpdate['member_user_a'], equals(1500.0));
      expect(balancesAfterUpdate['manual_user_b'], equals(-1500.0));
      // Double entry invariant: sum is exactly 0
      expect(balancesAfterUpdate['member_user_a']! + balancesAfterUpdate['manual_user_b']!, equals(0.0));

      // Settle balances should produce exactly 1 transaction: User B pays User A 1500
      final txs = settleBalances(members, balancesAfterUpdate);
      expect(txs.length, equals(1));
      expect(txs.first.fromMemberId, equals('manual_user_b'));
      expect(txs.first.toMemberId, equals('member_user_a'));
      expect(txs.first.amount, equals(1500.0));

      // Once receiver confirms the 1400 payment:
      final confirmedSettlement = SettlementRecord(
        id: 'set_1',
        fromMemberId: 'firebase_uid_a',
        fromName: 'User A',
        toMemberId: 'manual_user_b',
        toName: 'User B',
        amount: 1400.0,
        settledAt: DateTime.now(),
        status: SettlementStatus.confirmed,
        createdBy: 'firebase_uid_a',
      );

      final balancesAfterConfirmation = computeMemberBalances(
        members: members,
        expenses: [updatedExpense1],
        settlements: [confirmedSettlement],
      );

      // User A paid 3000 (net +1500) and gave 1400 settlement (+1400) -> total +2900
      expect(balancesAfterConfirmation['member_user_a'], equals(2900.0));
      expect(balancesAfterConfirmation['manual_user_b'], equals(-2900.0));
      expect(balancesAfterConfirmation['member_user_a']! + balancesAfterConfirmation['manual_user_b']!, equals(0.0));
    });

    test('Canonical ID resolution handles fragmented ID variants properly', () {
      final members = [
        GroupMember(id: 'm1', uid: 'uid_1', name: 'Alice', phoneNumber: '+919111111111'),
        GroupMember(id: 'm2', uid: 'uid_2', name: 'Bob', phoneNumber: '+919222222222'),
      ];

      expect(resolveCanonicalMemberId('m1', members), equals('m1'));
      expect(resolveCanonicalMemberId('uid_1', members), equals('m1'));
      expect(resolveCanonicalMemberId('+919111111111', members), equals('m1'));
      expect(resolveCanonicalMemberId('9111111111', members), equals('m1'));
      expect(resolveCanonicalMemberId('uid_2', members), equals('m2'));
      expect(resolveCanonicalMemberId('+919222222222', members), equals('m2'));
    });
  });
}
