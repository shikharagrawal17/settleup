import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/expense.dart';
import '../models/settlement_group.dart';
import '../models/settlement_record.dart';
import 'settlement_helper.dart';

class ReportHelper {
  static Future<void> exportToCsv(SettlementGroup group, List<Expense> expenses) async {
    final List<List<dynamic>> rows = [];

    // Header
    rows.add(["Date", "Description", "Payer", "Category", "Amount", "Currency"]);

    final memberMap = {for (final m in group.members) m.id: m.name};

    for (var expense in expenses) {
      rows.add([
        expense.createdAt.toLocal().toString().split('.')[0],
        expense.description,
        memberMap[expense.payerId] ?? 'Unknown',
        expense.resolvedCategory.label,
        expense.amount,
        expense.currency,
      ]);
    }

    final String csvData = const ListToCsvConverter().convert(rows);
    final Uint8List bytes = Uint8List.fromList(utf8.encode(csvData));

    final sanitizedGroupName = group.name.replaceAll(RegExp(r'[^\w\s-]'), '_').replaceAll(' ', '_');
    await Printing.sharePdf(bytes: bytes, filename: '${sanitizedGroupName}_expenses.csv');
  }

  static Future<void> exportToPdf(SettlementGroup group, List<Expense> expenses, List<SettlementRecord> settlements) async {
    final pdf = pw.Document();
    final memberMap = {for (final m in group.members) m.id: m.name};

    final balances = group.netBalances.isNotEmpty
        ? group.netBalances
        : computeMemberBalances(
            members: group.members,
            expenses: expenses,
            settlements: settlements,
          );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('Expense Report: ${group.name}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Generated on: ${DateTime.now().toLocal().toString().split('.')[0]}'),
            pw.SizedBox(height: 20),
            pw.Text('Expenses', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Description', 'Payer', 'Amount'],
              data: expenses.map((e) => [
                e.createdAt.toLocal().toString().split(' ')[0],
                e.description,
                memberMap[e.payerId] ?? 'Unknown',
                '${formatAmount(e.amount)} ${e.currency}'
              ]).toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Final Balances', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Member', 'Balance'],
              data: group.members.map((m) {
                final balance = balances[m.id] ?? 0.0;
                return [m.name, '${balance >= 0 ? '+' : ''}${formatAmount(balance)} ${group.currency}'];
              }).toList(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}
