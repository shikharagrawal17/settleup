class SettlementTransaction {
  SettlementTransaction({
    required this.fromMemberId,
    required this.fromName,
    required this.toMemberId,
    required this.toName,
    required this.amount,
    this.payeeUpiId,
    this.payerPhoneNumber,
    this.payeePhoneNumber,
  });

  final String fromMemberId;
  final String fromName;
  final String toMemberId;
  final String toName;
  final double amount;
  final String? payeeUpiId;
  final String? payerPhoneNumber;
  final String? payeePhoneNumber;
}
