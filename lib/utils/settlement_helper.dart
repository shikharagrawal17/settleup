import '../models/expense.dart';
import '../models/group_member.dart';
import '../models/settlement_record.dart';
import '../models/settlement_transaction.dart';

List<double> buildEqualSplit({
  required double total,
  required int memberCount,
}) {
  if (memberCount <= 0) {
    return const [];
  }

  // Use cents (2 decimal precision) for accurate splitting
  final int totalCents = (total * 100).round();
  final int baseCents = totalCents ~/ memberCount;
  final int remainderCents = totalCents % memberCount;

  return List<double>.generate(
    memberCount,
    (index) => (baseCents + (index < remainderCents ? 1 : 0)) / 100.0,
  );
}

/// Builds equal shares as a map of memberId → share amount.
Map<String, double> buildEqualShareMap({
  required double total,
  required List<GroupMember> members,
}) {
  final shares = buildEqualSplit(total: total, memberCount: members.length);
  return {
    for (var i = 0; i < members.length; i++) members[i].id: shares[i],
  };
}

/// Builds percentage-based shares.
Map<String, double> buildPercentageShareMap({
  required double total,
  required List<GroupMember> members,
  required Map<String, double> percentages,
}) {
  final result = <String, double>{};
  int totalCents = (total * 100).round();
  int assignedCents = 0;

  for (var i = 0; i < members.length; i++) {
    final pct = percentages[members[i].id] ?? 0;
    final shareCents = (totalCents * pct / 100).round();
    result[members[i].id] = shareCents / 100.0;
    assignedCents += shareCents;
  }

  // Fix rounding error if the sum of percentages is very close to 100.
  final totalPct = percentages.values.fold<double>(0.0, (sum, v) => sum + v);
  if (members.isNotEmpty && (totalPct - 100.0).abs() < 0.05) {
    if (assignedCents != totalCents) {
      final lastId = members.last.id;
      final currentLastCents = (result[lastId]! * 100).round();
      result[lastId] = (currentLastCents + (totalCents - assignedCents)) / 100.0;
    }
  }

  return result;
}

/// Builds shares-multiplier-based shares (1x, 2x, 3x etc).
Map<String, double> buildMultiplierShareMap({
  required double total,
  required List<GroupMember> members,
  required Map<String, double> multipliers,
}) {
  final totalMultiplier = multipliers.values.fold<double>(0, (s, v) => s + v);

  if (totalMultiplier <= 0) {
    return buildEqualShareMap(total: total, members: members);
  }

  final result = <String, double>{};
  int totalCents = (total * 100).round();
  int assignedCents = 0;

  for (var i = 0; i < members.length; i++) {
    final mult = multipliers[members[i].id] ?? 1.0;
    final shareCents = (totalCents * mult / totalMultiplier).round();
    result[members[i].id] = shareCents / 100.0;
    assignedCents += shareCents;
  }

  // Fix rounding error on last member.
  if (members.isNotEmpty && assignedCents != totalCents) {
    final lastId = members.last.id;
    final currentLastCents = (result[lastId]! * 100).round();
    result[lastId] = (currentLastCents + (totalCents - assignedCents)) / 100.0;
  }

  return result;
}

/// Computes the net balance for every member across expenses and settlements.
/// Positive = member is owed money (gets back). Negative = member owes money.
Map<String, double> computeMemberBalances({
  required List<GroupMember> members,
  required List<Expense> expenses,
  required List<SettlementRecord> settlements,
}) {
  final balances = <String, double>{};
  for (final m in members) {
    balances[m.id] = 0.0;
  }

  // Expenses: payer credited, each share debited.
  for (final expense in expenses) {
    balances[expense.payerId] =
        (balances[expense.payerId] ?? 0.0) + expense.amount;
    for (final entry in expense.shares.entries) {
      balances[entry.key] = (balances[entry.key] ?? 0.0) - entry.value;
    }
  }

  // Settlements: payer (from) balance goes up, payee (to) balance goes down.
  for (final s in settlements) {
    if (s.status == SettlementStatus.confirmed) {
      balances[s.fromMemberId] = (balances[s.fromMemberId] ?? 0.0) + s.amount;
      balances[s.toMemberId] = (balances[s.toMemberId] ?? 0.0) - s.amount;
    }
  }

  return balances;
}

/// Simplifies a single expense into transactions.
List<SettlementTransaction> simplifyTransactions({
  required List<GroupMember> members,
  required String payerId,
  required double totalAmount,
  required Map<String, double> shares,
}) {
  if (totalAmount <= 0) {
    return const [];
  }

  final assignedTotal = shares.values.fold<double>(0, (sum, amount) => sum + amount);
  if ((assignedTotal - totalAmount).abs() > 0.01) {
    return const [];
  }

  final balances = <String, double>{};
  for (final member in members) {
    balances[member.id] = -((shares[member.id] ?? 0.0));
  }
  balances[payerId] = (balances[payerId] ?? 0.0) + totalAmount;

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

  final balances = <String, double>{};
  for (final member in members) {
    balances[member.id] = 0.0;
  }

  for (final expense in expenses) {
    balances[expense.payerId] =
        (balances[expense.payerId] ?? 0.0) + expense.amount;
    for (final entry in expense.shares.entries) {
      balances[entry.key] = (balances[entry.key] ?? 0.0) - entry.value;
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
  Map<String, double> balances,
) {
  final memberMap = {for (final m in members) m.id: m};

  final creditors = <_BalanceNode>[];
  final debtors = <_BalanceNode>[];

  for (final entry in balances.entries) {
    final member = memberMap[entry.key];
    if (member == null) continue;
    // Use a small epsilon to avoid settling tiny rounding errors
    if (entry.value > 0.005) {
      creditors.add(_BalanceNode(member: member, amount: entry.value));
    } else if (entry.value < -0.005) {
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

    if (creditor.amount < 0.005) {
      creditorIndex++;
    }
    if (debtor.amount < 0.005) {
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
  double amount;
}

String formatAmount(double amount) {
  // If it's a whole number, show no decimals
  if (amount == amount.toInt().toDouble()) {
    return amount.toInt().toString();
  }
  // Otherwise show up to 2 decimals, removing unnecessary trailing zeros
  String s = amount.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}
