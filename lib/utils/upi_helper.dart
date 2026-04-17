import '../models/settlement_transaction.dart';

bool isValidUpiId(String value) {
  final normalized = value.trim();
  final regex = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');
  return regex.hasMatch(normalized);
}

String generateUpiLink({
  required String upiId,
  required String payeeName,
  required double amount,
}) {
  final encodedName = Uri.encodeComponent(payeeName);
  return 'upi://pay?pa=$upiId&pn=$encodedName&am=$amount&cu=INR';
}

String buildSettlementShareMessage({
  required String groupName,
  required List<SettlementTransaction> transactions,
}) {
  final buffer = StringBuffer('💸 $groupName settlement\n\n');

  for (final transaction in transactions) {
    buffer.writeln('${transaction.fromName} pays ${transaction.toName} - ₹${transaction.amount}');
    if (transaction.payeeUpiId != null) {
      buffer.writeln(
        generateUpiLink(
          upiId: transaction.payeeUpiId!,
          payeeName: transaction.toName,
          amount: transaction.amount,
        ),
      );
    }
    buffer.writeln();
  }

  return buffer.toString().trim();
}
