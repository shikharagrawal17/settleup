import '../models/expense.dart';
import '../models/group_member.dart';
import '../models/settlement_record.dart';
import '../models/settlement_transaction.dart';

List<int> buildEqualSplit({
  required int total,
  required int memberCount,
}) {
  if (memberCount <= 0) {
    return const [];
  }

  final base = total ~/ memberCount;
  final remainder = total % memberCount;

  return List<int>.generate(
    memberCount,
    (index) => base + (index < remainder ? 1 : 0),
  );
}

/// Builds equal shares as a map of memberId → share amount.
Map<String, int> buildEqualShareMap({
  required int total,
  required List<GroupMember> members,
}) {
  final shares = buildEqualSplit(total: total, memberCount: members.length);
  return {
    for (var i = 0; i < members.length; i++) members[i].id: shares[i],
  };
}

/// Builds percentage-based shares.
Map<String, int> buildPercentageShareMap({
  required int total,
  required List<GroupMember> members,
  required Map<String, double> percentages,
}) {
  final result = <String, int>{};
  var assigned = 0;

  for (var i = 0; i < members.length; i++) {
    final pct = percentages[members[i].id] ?? 0;
    final share = (total * pct / 100).round();
    result[members[i].id] = share;
    assigned += share;
  }

  // Fix rounding error on last member.
  if (members.isNotEmpty && assigned != total) {
    result[members.last.id] = (result[members.last.id] ?? 0) + (total - assigned);
  }

  return result;
}

/// Builds shares-multiplier-based shares (1x, 2x, 3x etc).
Map<String, int> buildMultiplierShareMap({
  required int total,
  required List<GroupMember> members,
  required Map<String, int> multipliers,
}) {
  final totalMultiplier = multipliers.values.fold<int>(0, (s, v) => s + v);

  if (totalMultiplier <= 0) {
    return buildEqualShareMap(total: total, members: members);
  }

  final result = <String, int>{};
  var assigned = 0;

  for (var i = 0; i < members.length; i++) {
    final mult = multipliers[members[i].id] ?? 1;
    final share = (total * mult / totalMultiplier).round();
    result[members[i].id] = share;
    assigned += share;
  }

  // Fix rounding error on last member.
  if (members.isNotEmpty && assigned != total) {
    result[members.last.id] = (result[members.last.id] ?? 0) + (total - assigned);
  }

  return result;
}

/// Computes the net balance for every member across expenses and settlements.
/// Positive = member is owed money (gets back). Negative = member owes money.
Map<String, int> computeMemberBalances({
  required List<GroupMember> members,
  required List<Expense> expenses,
  required List<SettlementRecord> settlements,
}) {
  final balances = <String, int>{};
  for (final m in members) {
    balances[m.id] = 0;
  }

  // Expenses: payer credited, each share debited.
  for (final expense in expenses) {
    balances[expense.payerId] =
        (balances[expense.payerId] ?? 0) + expense.amount;
    for (final entry in expense.shares.entries) {
      balances[entry.key] = (balances[entry.key] ?? 0) - entry.value;
    }
  }

  // Settlements: payer (from) balance goes up, payee (to) balance goes down.
  for (final s in settlements) {
    balances[s.fromMemberId] = (balances[s.fromMemberId] ?? 0) + s.amount;
    balances[s.toMemberId] = (balances[s.toMemberId] ?? 0) - s.amount;
  }

  return balances;
}

/// Simplifies a single expense into transactions (backward compat).
List<SettlementTransaction> simplifyTransactions({
  required List<GroupMember> members,
  required String payerId,
  required int totalAmount,
  required Map<String, int> shares,
}) {
  if (totalAmount <= 0) {
    return const [];
  }

  final assignedTotal = shares.values.fold<int>(0, (sum, amount) => sum + amount);
  if (assignedTotal != totalAmount) {
    return const [];
  }

  final balances = <String, int>{};
  for (final member in members) {
    balances[member.id] = -((shares[member.id] ?? 0));
  }
  balances[payerId] = (balances[payerId] ?? 0) + totalAmount;

  return _settleBalances(members, balances);
}

/// Simplifies multiple expenses across a group into the minimum set of transfers.
List<SettlementTransaction> simplifyMultipleExpenses({
  required List<GroupMember> members,
  required List<Expense> expenses,
}) {
  if (expenses.isEmpty) {
    return const [];
  }

  final balances = <String, int>{};
  for (final member in members) {
    balances[member.id] = 0;
  }

  for (final expense in expenses) {
    balances[expense.payerId] =
        (balances[expense.payerId] ?? 0) + expense.amount;
    for (final entry in expense.shares.entries) {
      balances[entry.key] = (balances[entry.key] ?? 0) - entry.value;
    }
  }

  return _settleBalances(members, balances);
}

/// Simplifies expenses minus already-settled amounts.
List<SettlementTransaction> simplifyWithSettlements({
  required List<GroupMember> members,
  required List<Expense> expenses,
  required List<SettlementRecord> settlements,
}) {
  final balances = computeMemberBalances(
    members: members,
    expenses: expenses,
    settlements: settlements,
  );

  return _settleBalances(members, balances);
}

List<SettlementTransaction> _settleBalances(
  List<GroupMember> members,
  Map<String, int> balances,
) {
  final memberMap = {for (final m in members) m.id: m};

  final creditors = <_BalanceNode>[];
  final debtors = <_BalanceNode>[];

  for (final entry in balances.entries) {
    final member = memberMap[entry.key];
    if (member == null) continue;
    if (entry.value > 0) {
      creditors.add(_BalanceNode(member: member, amount: entry.value));
    } else if (entry.value < 0) {
      debtors.add(_BalanceNode(member: member, amount: -entry.value));
    }
  }

  final transactions = <SettlementTransaction>[];
  var creditorIndex = 0;
  var debtorIndex = 0;

  while (creditorIndex < creditors.length && debtorIndex < debtors.length) {
    final creditor = creditors[creditorIndex];
    final debtor = debtors[debtorIndex];
    final amount =
        creditor.amount < debtor.amount ? creditor.amount : debtor.amount;

    transactions.add(
      SettlementTransaction(
        fromMemberId: debtor.member.id,
        fromName: debtor.member.name,
        toMemberId: creditor.member.id,
        toName: creditor.member.name,
        amount: amount,
        payeeUpiId: creditor.member.upiId,
        payerPhoneNumber: debtor.member.phoneNumber,
      ),
    );

    creditor.amount -= amount;
    debtor.amount -= amount;

    if (creditor.amount == 0) {
      creditorIndex++;
    }
    if (debtor.amount == 0) {
      debtorIndex++;
    }
  }

  return transactions;
}

class _BalanceNode {
  _BalanceNode({
    required this.member,
    required this.amount,
  });

  final GroupMember member;
  int amount;
}
