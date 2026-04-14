class SettlementTransaction {
  SettlementTransaction({
    required this.fromMemberId,
    required this.fromName,
    required this.toMemberId,
    required this.toName,
    required this.amount,
    this.payeeUpiId,
    this.payerPhoneNumber,
  });

  final String fromMemberId;
  final String fromName;
  final String toMemberId;
  final String toName;
  final int amount;
  final String? payeeUpiId;
  final String? payerPhoneNumber;
}
