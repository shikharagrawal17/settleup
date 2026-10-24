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

  // Fix rounding error if the sum of percentages is close to 100 (handles integer 33% + 33% + 33% = 99%).
  final totalPct = percentages.values.fold<double>(0.0, (sum, v) => sum + v);
  if (members.isNotEmpty && (totalPct - 100.0).abs() <= 1.05) {
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

String _cleanPhoneDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '+91$digits';
  if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
  if (digits.length == 11 && digits.startsWith('0')) return '+91${digits.substring(1)}';
  if (raw.startsWith('+')) return '+$digits';
  return digits;
}

/// Builds an O(1) canonical member resolution index for high-speed lookups.
Map<String, String> buildCanonicalMemberIndex(List<GroupMember> members) {
  final index = <String, String>{};
  for (final m in members) {
    index[m.id] = m.id;
    if (m.uid != null && m.uid!.isNotEmpty) {
      index[m.uid!] = m.id;
    }
    if (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) {
      final clean = _cleanPhoneDigits(m.phoneNumber!);
      if (clean.isNotEmpty) {
        index[clean] = m.id;
        final rawDigits = m.phoneNumber!.replaceAll(RegExp(r'\D'), '');
        if (rawDigits.isNotEmpty) {
          index[rawDigits] = m.id;
          if (rawDigits.length >= 10) {
            index[rawDigits.substring(rawDigits.length - 10)] = m.id;
          }
        }
      }
    }
  }
  return index;
}

/// Resolves any member identifier (m.id, m.uid, or phone number)
/// to the single canonical GroupMember.id within the group.
String resolveCanonicalMemberId(String rawId, List<GroupMember> members, [Map<String, String>? index]) {
  if (rawId.isEmpty) return rawId;
  final lookup = index ?? buildCanonicalMemberIndex(members);
  final direct = lookup[rawId];
  if (direct != null) return direct;
  final cleanRaw = _cleanPhoneDigits(rawId);
  final phoneMatch = lookup[cleanRaw];
  if (phoneMatch != null) return phoneMatch;
  return rawId;
}

/// Computes the net balance for every member across expenses and settlements.
/// Positive = member is owed money (gets back). Negative = member owes money.
Map<String, double> computeMemberBalances({
  required List<GroupMember> members,
  required List<Expense> expenses,
  required List<SettlementRecord> settlements,
}) {
  final canonIndex = buildCanonicalMemberIndex(members);
  final balances = <String, double>{};
  for (final m in members) {
    balances[m.id] = 0.0;
  }

  // Expenses: payer credited, each share debited.
  // All member identifiers are mapped via O(1) canonical lookup.
  for (final expense in expenses) {
    final scale = (expense.baseAmount != null && expense.amount > 0) 
        ? (expense.baseAmount! / expense.amount) 
        : 1.0;
        
    final effectiveAmount = expense.baseAmount ?? expense.amount;

    final canonPayerId = resolveCanonicalMemberId(expense.payerId, members, canonIndex);
    balances[canonPayerId] = (balances[canonPayerId] ?? 0.0) + effectiveAmount;

    for (final entry in expense.shares.entries) {
      final canonShareId = resolveCanonicalMemberId(entry.key, members, canonIndex);
      balances[canonShareId] = (balances[canonShareId] ?? 0.0) - (entry.value * scale);
    }
  }

  // Settlements: payer (from) balance goes up, payee (to) balance goes down.
  for (final s in settlements) {
    if (s.status == SettlementStatus.confirmed) {
      final canonFromId = resolveCanonicalMemberId(s.fromMemberId, members, canonIndex);
      final canonToId = resolveCanonicalMemberId(s.toMemberId, members, canonIndex);
      balances[canonFromId] = (balances[canonFromId] ?? 0.0) + s.amount;
      balances[canonToId] = (balances[canonToId] ?? 0.0) - s.amount;
    }
  }

  // Precision Guardrail: Clean floating point noise (-0.0 -> 0.0, 0.0000000001 -> 0.0)
  for (final key in balances.keys.toList()) {
    final raw = balances[key]!;
    if (raw.abs() < 0.005) {
      balances[key] = 0.0;
    } else {
      balances[key] = (raw * 100).round() / 100.0;
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

  return settleBalances(members, balances);
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
    final scale = (expense.baseAmount != null && expense.amount > 0)
        ? (expense.baseAmount! / expense.amount)
        : 1.0;
    final effectiveAmount = expense.baseAmount ?? expense.amount;

    balances[expense.payerId] =
        (balances[expense.payerId] ?? 0.0) + effectiveAmount;
    for (final entry in expense.shares.entries) {
      balances[entry.key] =
          (balances[entry.key] ?? 0.0) - (entry.value * scale);
    }
  }

  return settleBalances(members, balances);
}

/// Given a set of accounting IDs belonging to the current user within a group
/// and the group's simplified transactions, computes bilateral net debt with each other member.
/// Positive value = friend owes user money.
/// Negative value = user owes friend money.
Map<String, double> computePairwiseBilateralDebts({
  required Set<String> myMemberIds,
  required List<SettlementTransaction> transactions,
}) {
  final Map<String, double> bilateralDebts = {};

  for (final tx in transactions) {
    final bool fromIsMe = myMemberIds.contains(tx.fromMemberId);
    final bool toIsMe = myMemberIds.contains(tx.toMemberId);

    if (fromIsMe && toIsMe) {
      continue; // Internal transfer between user's own linked identities
    }

    if (fromIsMe) {
      // User owes 'toMemberId' this amount
      bilateralDebts[tx.toMemberId] =
          (bilateralDebts[tx.toMemberId] ?? 0.0) - tx.amount;
    } else if (toIsMe) {
      // 'fromMemberId' owes user this amount
      bilateralDebts[tx.fromMemberId] =
          (bilateralDebts[tx.fromMemberId] ?? 0.0) + tx.amount;
    }
  }

  return bilateralDebts;
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

  return settleBalances(members, balances);
}

List<SettlementTransaction> settleBalances(
  List<GroupMember> members,
  Map<String, double> balances,
) {
  final memberMap = {for (final m in members) m.id: m};

  // Reconcile and canonicalize incoming balances map so no transactions are dropped
  final canonicalBalances = <String, double>{};
  for (final m in members) {
    canonicalBalances[m.id] = 0.0;
  }
  for (final entry in balances.entries) {
    final canonId = resolveCanonicalMemberId(entry.key, members);
    canonicalBalances[canonId] = (canonicalBalances[canonId] ?? 0.0) + entry.value;
  }

  final creditors = <_BalanceNode>[];
  final debtors = <_BalanceNode>[];

  for (final entry in canonicalBalances.entries) {
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
        payeePhoneNumber: creditor.member.phoneNumber,
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

String getCurrencySymbol(String currencyCode) {
  switch (currencyCode.toUpperCase()) {
    case 'INR':
      return '₹';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'JPY':
      return '¥';
    default:
      return currencyCode;
  }
}
