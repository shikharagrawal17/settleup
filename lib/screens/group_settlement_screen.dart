import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/expense.dart';
import '../models/group_member.dart';
import '../models/settlement_group.dart';
import '../models/settlement_record.dart';
import '../models/settlement_transaction.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../utils/settlement_helper.dart';
import '../utils/upi_helper.dart';
import '../widgets/app_shell_widgets.dart';
import 'edit_group_screen.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────

String _getMonth(DateTime d) {
  const m = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  return m[d.month - 1];
}

String _formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]}';
}

String _formatMonthYear(DateTime d) {
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${months[d.month - 1]} ${d.year}';
}

// ─── Main screen ─────────────────────────────────────────────────────────

class GroupSettlementScreen extends StatefulWidget {
  const GroupSettlementScreen({
    super.key,
    required this.group,
    required this.profile,
  });

  final SettlementGroup group;
  final UserProfile profile;

  @override
  State<GroupSettlementScreen> createState() => _GroupSettlementScreenState();
}

class _GroupSettlementScreenState extends State<GroupSettlementScreen> {
  late SettlementGroup _group;
  bool _simplifyDebts = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _group = widget.group;
  }


  void _openAnalytics(AppState appState, List<Expense> expenses) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AnalyticsSheet(
        expenses: expenses,
        group: _group,
      ),
    );
  }

  void _openSettleSheet(BuildContext context, AppState appState, List<SettlementTransaction> transactions, Map<String, GroupMember> memberMap) {
     showModalBottomSheet<void>(
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
       useSafeArea: true,
       builder: (c) => Container(
         decoration: const BoxDecoration(
           color: Color(0xFF141414),
           borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
         ),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             const SizedBox(height: 12),
             Container(
               height: 5,
               width: 40,
               decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
             ),
             const SizedBox(height: 12),
             Flexible(
               child: _SettleTab(
                  memberMap: memberMap,
                 transactions: transactions,
                 currentUserId: _currentUserId,
                onPay: (t) => _launchUpi(t, appState),
                 onRecord: (t) => _openRecordSettlement(appState, t),
                 onRemind: _sendWhatsappReminder,
               ),
             ),
           ],
         ),
       ),
     );
  }

  void _openBalancesSheet(BuildContext context, Map<String, int> balances, List<SettlementTransaction> transactions, List<GroupMember> resolvedMembers) {
     showModalBottomSheet<void>(
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
       useSafeArea: true,
       builder: (c) => Container(
         decoration: const BoxDecoration(
           color: Color(0xFF141414),
           borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
         ),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             const SizedBox(height: 8),
             Container(
               height: 5,
               width: 40,
               decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
             ),
             const SizedBox(height: 16),
             Flexible(
               child: _BalancesTab(
                 resolvedMembers: resolvedMembers,
                 balances: balances,
                 currentUserId: _currentUserId,
                 transactions: transactions,
               ),
             ),
           ],
         ),
       ),
     );
  }

  List<GroupMember> _resolveAll(List<GroupMember> groupMembers, Map<String, UserProfile> liveProfiles) {
    final appState = context.read<AppState>();
    return groupMembers.map((member) {
      final live = liveProfiles[member.id];
      final baseMember = live == null 
        ? member 
        : member.copyWith(
            name: live.displayName,
            upiId: live.upiId,
            phoneNumber: live.phoneNumber,
          );
      
      return baseMember.copyWith(
        name: appState.resolveMemberName(baseMember),
        isSelf: baseMember.id == _currentUserId,
      );
    }).toList();
  }

  String get _currentUserId => widget.profile.uid;

  Future<void> _launchUpi(SettlementTransaction transaction, AppState appState) async {
    if (transaction.payeeUpiId == null) return;
    final link = generateUpiLink(
      upiId: transaction.payeeUpiId!,
      payeeName: transaction.toName,
      amount: transaction.amount,
    );
    final launched = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    
    if (!mounted) return;

    if (launched) {
      if (!mounted) return;
      
      // Since UPI apps don't return a status callback, we ask the user to confirm success.
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: AppSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   const Icon(Icons.help_outline, color: kAccent, size: 40),
                   const SizedBox(height: 16),
                   const Text('Confirm Payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                   const SizedBox(height: 12),
                   Text(
                     'Did you successfully complete the payment of ₹${transaction.amount} in your UPI app?',
                     textAlign: TextAlign.center,
                     style: const TextStyle(color: Colors.white70),
                   ),
                   const SizedBox(height: 24),
                   Row(
                     children: [
                       Expanded(
                         child: OutlinedButton(
                           onPressed: () => Navigator.pop(ctx, false),
                           child: const Text('No'),
                         ),
                       ),
                       const SizedBox(width: 12),
                       Expanded(
                         child: FilledButton(
                           onPressed: () => Navigator.pop(ctx, true),
                           child: const Text('Yes, Record'),
                         ),
                       ),
                     ],
                   )
                ],
              ),
            ),
          ),
        ),
      );

      if (confirmed == true && mounted) {
        final record = SettlementRecord(
          id: '',
          fromMemberId: transaction.fromMemberId,
          fromName: transaction.fromName,
          toMemberId: transaction.toMemberId,
          toName: transaction.toName,
          amount: transaction.amount,
          note: 'Paid via UPI',
          settledAt: DateTime.now(),
          createdBy: widget.profile.uid,
        );

        await appState.addSettlement(groupId: _group.id, record: record);
        
        if (mounted) {
          Navigator.of(context).pop(); // Close the settle sheet
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment confirmed and recorded!')),
          );
        }
      }
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open a UPI app on this device.')),
    );
  }

  void _share(List<SettlementTransaction> transactions) {
    final message = buildSettlementShareMessage(
      groupName: _group.name,
      transactions: transactions,
    );
    Share.share(message, subject: '${_group.name} settlement');
  }

  Future<void> _sendWhatsappReminder(SettlementTransaction transaction) async {
    final phone = transaction.payerPhoneNumber;
    if (phone == null || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No phone number saved for ${transaction.fromName}.')),
        );
      }
      return;
    }
    
    final message = "Hey ${transaction.fromName}, just a quick nudge to settle up ₹${transaction.amount} for '${_group.name}' on SettleUp! ${transaction.payeeUpiId != null ? 'My UPI is ${transaction.payeeUpiId}. ' : ''}Thanks 💸";
    final url = Uri.parse('whatsapp://send?phone=$phone&text=${Uri.encodeComponent(message)}');
    
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        throw Exception('Could not launch WhatsApp');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('WhatsApp is not installed or cannot be opened.')),
        );
      }
    }
  }

  Future<void> _openEditGroup(
    AppState appState,
    List<Expense> expenses,
    List<SettlementRecord> settlements,
  ) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditGroupScreen(
          group: _group,
          expenses: expenses,
          settlements: settlements,
          currentUserId: _currentUserId,
        ),
      ),
    );
    if (updated == true && mounted) {
      // The group stream will auto-refresh. We just need to pop and re-enter
      // or use groupStream. Let's use groupStream.
    }
  }

  // ─── Add expense bottom sheet ─────────────────────────────────────────

  Future<void> _openAddEditExpense(AppState appState, List<GroupMember> resolvedMembers, {Expense? initialExpense}) async {
    final descCtrl = TextEditingController(text: initialExpense?.description ?? '');
    final amountCtrl = TextEditingController(text: (initialExpense?.amount ?? 0) > 0 ? initialExpense!.amount.toString() : '');
    final formKey = GlobalKey<FormState>();
    String payerId = initialExpense?.payerId ?? resolvedMembers.first.id;
    SplitMode splitMode = initialExpense == null ? SplitMode.equal : SplitMode.exact;
    
    // Track who is included in this split
    final includedIds = initialExpense == null 
        ? resolvedMembers.map((m) => m.id).toSet() 
        : initialExpense.shares.entries.where((e) => e.value > 0).map((e) => e.key).toSet();

    final shareControllers = {
      for (final m in resolvedMembers) m.id: TextEditingController(
        text: initialExpense?.shares[m.id]?.toString() ?? '',
      ),
    };
    final pctControllers = {
      for (final m in resolvedMembers) m.id: TextEditingController(
        text: initialExpense != null && initialExpense.amount > 0 && (initialExpense.shares[m.id] ?? 0) > 0 
          ? ((initialExpense.shares[m.id] ?? 0) / initialExpense.amount * 100).toStringAsFixed(0) 
          : ''
      ),
    };
    final multControllers = {
      for (final m in resolvedMembers) m.id: TextEditingController(text: '1'),
    };
    ExpenseCategory selectedCategory = initialExpense?.category ?? ExpenseCategory.other;
    bool isCategoryManual = initialExpense != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void recomputeShares() {
              final total = int.tryParse(amountCtrl.text.trim()) ?? 0;
              if (total == 0) return;

              final includedMembers = resolvedMembers.where((m) => includedIds.contains(m.id)).toList();

              switch (splitMode) {
                case SplitMode.equal:
                  final shares = buildEqualShareMap(total: total, members: includedMembers);
                  for (final m in resolvedMembers) {
                    shareControllers[m.id]!.text = (shares[m.id] ?? 0).toString();
                  }
                case SplitMode.percentage:
                  final pcts = <String, double>{};
                  for (final m in includedMembers) {
                    pcts[m.id] = double.tryParse(pctControllers[m.id]!.text.trim()) ?? 0;
                  }
                  final shares = buildPercentageShareMap(total: total, members: includedMembers, percentages: pcts);
                  for (final m in resolvedMembers) {
                    shareControllers[m.id]!.text = (shares[m.id] ?? 0).toString();
                  }
                case SplitMode.shares:
                  final mults = <String, int>{};
                  for (final m in includedMembers) {
                    mults[m.id] = int.tryParse(multControllers[m.id]!.text.trim()) ?? 1;
                  }
                  final shares = buildMultiplierShareMap(total: total, members: includedMembers, multipliers: mults);
                  for (final m in resolvedMembers) {
                    shareControllers[m.id]!.text = (shares[m.id] ?? 0).toString();
                  }
                case SplitMode.exact:
                  break; 
              }
            }

            if (splitMode != SplitMode.exact) {
              recomputeShares();
            }

            final totalExpense = int.tryParse(amountCtrl.text.trim()) ?? 0;
            final sumOfShares = shareControllers.values.fold<int>(0, (sum, ctrl) => sum + (int.tryParse(ctrl.text.trim()) ?? 0));
            final isBalanced = totalExpense == sumOfShares;
            final diff = totalExpense - sumOfShares;

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, scrollController) => AppSurface(
                padding: EdgeInsets.zero,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Form(
                  key: formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                            const SizedBox(height: 20),
                      TextFormField(
                        controller: descCtrl,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Dinner, Groceries, Rent...',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                        onChanged: (v) => setSheetState(() {
                          if (!isCategoryManual) {
                            selectedCategory = ExpenseCategory.detect(v);
                          }
                        }),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      // Modern Category Selector
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ExpenseCategory.values.map((cat) {
                            final isSelected = selectedCategory == cat;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                showCheckmark: false,
                                avatar: Icon(cat.icon, size: 14, color: isSelected ? Colors.black : Colors.white70),
                                label: Text(cat.label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w800 : FontWeight.normal, color: isSelected ? Colors.black : Colors.white70)),
                                selected: isSelected,
                                onSelected: (_) => setSheetState(() {
                                  selectedCategory = cat;
                                  isCategoryManual = true;
                                }),
                                selectedColor: kAccent,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Core Details: Amount and Payer
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: amountCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: kAccent),
                              decoration: const InputDecoration(
                                labelText: 'Total Amount',
                                prefixText: '₹ ',
                                alignLabelWithHint: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (_) => setSheetState(() {
                                if (splitMode != SplitMode.exact) recomputeShares();
                              }),
                              validator: (v) {
                                final val = int.tryParse((v ?? '').trim());
                                return (val == null || val <= 0) ? '!' : null;
                              },
                            ),
                            const Divider(height: 32, color: Colors.white10),
                            DropdownButtonFormField<String>(
                              value: payerId,
                              dropdownColor: Colors.black87,
                              decoration: const InputDecoration(
                                labelText: 'Paid By',
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              items: resolvedMembers
                                  .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700))))
                                  .toList(),
                              onChanged: (v) { if (v != null) setSheetState(() => payerId = v); },
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),

                      // Professional Split Selector
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('SPLIT METHOD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1.5)),
                          Text(splitMode.label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: kAccent)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: SplitMode.values.map((m) {
                            final isSelected = splitMode == m;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                showCheckmark: false,
                                label: Text(m.label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w800 : FontWeight.normal, color: isSelected ? Colors.black : Colors.white70)),
                                selected: isSelected,
                                onSelected: (val) {
                                  if (val) {
                                    setSheetState(() {
                                      splitMode = m;
                                      recomputeShares();
                                    });
                                  }
                                },
                                selectedColor: kAccent,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Member Rows
                      ...resolvedMembers.map((m) {
                        final isIncluded = includedIds.contains(m.id);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isIncluded ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isIncluded ? kAccent.withValues(alpha: 0.1) : Colors.transparent),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setSheetState(() {
                              if (isIncluded) {
                                includedIds.remove(m.id);
                                shareControllers[m.id]!.text = '0';
                              } else {
                                includedIds.add(m.id);
                              }
                              recomputeShares();
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    isIncluded ? Icons.check_circle_rounded : Icons.circle_outlined,
                                    color: isIncluded ? kAccent : Colors.white24,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.name,
                                          style: TextStyle(
                                            fontSize: 15, 
                                            fontWeight: isIncluded ? FontWeight.w800 : FontWeight.w500,
                                            color: isIncluded ? Colors.white : Colors.white38,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (isIncluded && (splitMode == SplitMode.percentage || splitMode == SplitMode.shares))
                                          Text(
                                            splitMode == SplitMode.percentage 
                                              ? '${pctControllers[m.id]!.text}% Share'
                                              : '${multControllers[m.id]!.text}x Weight',
                                            style: const TextStyle(fontSize: 10, color: kAccent, fontWeight: FontWeight.w700),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isIncluded && (splitMode == SplitMode.percentage || splitMode == SplitMode.shares)) ...[
                                    SizedBox(
                                      width: 45,
                                      child: TextFormField(
                                        controller: splitMode == SplitMode.percentage ? pctControllers[m.id] : multControllers[m.id],
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                        decoration: InputDecoration(
                                          hintText: splitMode == SplitMode.percentage ? '%' : 'x',
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                          border: UnderlineInputBorder(borderSide: BorderSide(color: kAccent.withValues(alpha: 0.3))),
                                        ),
                                        onChanged: (_) => setSheetState(() => recomputeShares()),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  SizedBox(
                                    width: 75,
                                    child: TextFormField(
                                      controller: shareControllers[m.id],
                                      keyboardType: TextInputType.number,
                                      enabled: isIncluded && splitMode == SplitMode.exact,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 16, 
                                        fontWeight: FontWeight.w900, 
                                        color: isIncluded ? Colors.white : Colors.white10
                                      ),
                                      decoration: InputDecoration(
                                        prefixText: '₹ ',
                                        prefixStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (_) => setSheetState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      
                      const SizedBox(height: 24),
                      
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isBalanced ? kAccent.withValues(alpha: 0.1) : Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isBalanced ? 'BALANCED' : 'UNBALANCED',
                                    style: TextStyle(
                                      color: isBalanced ? kAccent : Colors.redAccent,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  Text(
                                    isBalanced ? 'All shares match total' : 'Remaining: ₹$diff',
                                    style: TextStyle(
                                      color: isBalanced ? Colors.white : Colors.redAccent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(120, 56),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              ),
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                final currentTotal = int.tryParse(amountCtrl.text.trim()) ?? 0;
                                final currentSum = shareControllers.values.fold<int>(0, (sum, ctrl) => sum + (int.tryParse(ctrl.text.trim()) ?? 0));
                                
                                if (currentTotal != currentSum) {
                                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: Colors.redAccent,
                                      content: Text('Total (₹$currentTotal) ≠ Shares (₹$currentSum)', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                  );
                                  return;
                                }

                                final shares = { for (final m in resolvedMembers) m.id: int.tryParse(shareControllers[m.id]!.text.trim()) ?? 0 };
                                
                                final expense = Expense(
                                  id: initialExpense?.id ?? '',
                                  description: descCtrl.text.trim(),
                                  amount: currentTotal,
                                  payerId: payerId,
                                  shares: shares,
                                  createdAt: initialExpense?.createdAt ?? DateTime.now(),
                                  createdBy: initialExpense?.createdBy ?? widget.profile.uid,
                                  category: selectedCategory,
                                );

                                if (initialExpense == null) {
                                  await appState.addExpense(groupId: _group.id, expense: expense);
                                } else {
                                  await appState.updateExpense(groupId: _group.id, oldExpense: initialExpense, newExpense: expense);
                                }
                                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                              },
                              icon: Icon(initialExpense == null ? Icons.add_rounded : Icons.check_rounded),
                              label: Text(initialExpense == null ? 'Add' : 'Update'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Record settlement bottom sheet ───────────────────────────────────

  Future<void> _openRecordSettlement(
    AppState appState,
    SettlementTransaction transaction,
  ) async {
    final amountCtrl = TextEditingController(text: transaction.amount.toString());
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16, 0, 16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: AppSurface(
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeading(
                    title: 'Record Payment',
                    subtitle: '${transaction.fromName} pays ${transaction.toName}',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                    validator: (v) {
                      final val = int.tryParse((v ?? '').trim());
                      if (val == null || val <= 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Note (optional)'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final record = SettlementRecord(
                          id: '',
                          fromMemberId: transaction.fromMemberId,
                          fromName: transaction.fromName,
                          toMemberId: transaction.toMemberId,
                          toName: transaction.toName,
                          amount: int.parse(amountCtrl.text.trim()),
                          settledAt: DateTime.now(),
                          createdBy: widget.profile.uid,
                          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                        );
                        await appState.addSettlement(groupId: _group.id, record: record);
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Record Payment'),
                    ),
                  ),
                ],
              ),
             ),
            ),
          ),
        );
      },
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    return StreamBuilder<SettlementGroup?>(
      stream: appState.groupStream(_group.id),
      builder: (context, groupSnap) {
        if (groupSnap.hasError) return _ErrorScaffold(error: groupSnap.error);
        if (groupSnap.hasData && groupSnap.data != null) {
          _group = groupSnap.data!;
        }

        return StreamBuilder<Map<String, UserProfile>>(
          stream: appState.profilesStream(_group.members.map((m) => m.id).toList()),
          builder: (context, profilesSnap) {
            final profiles = profilesSnap.data ?? {};
            final resolvedMembers = _resolveAll(_group.members, profiles);
            final memberMap = {for (var m in resolvedMembers) m.id: m};

            return StreamBuilder<List<Expense>>(
              stream: appState.expensesStream(_group.id),
              builder: (context, expSnap) {
                if (expSnap.hasError) return _ErrorScaffold(error: expSnap.error);
                final expenses = expSnap.data ?? const <Expense>[];

                return StreamBuilder<List<SettlementRecord>>(
                  stream: appState.settlementsStream(_group.id),
                  builder: (context, setSnap) {
                    if (setSnap.hasError) return _ErrorScaffold(error: setSnap.error);
                    final settlements = setSnap.data ?? const <SettlementRecord>[];
                    
                    final transactions = simplifyWithSettlements(
                      members: resolvedMembers,
                                      expenses: expenses,
                      settlements: settlements,
                    );
                    final balances = computeMemberBalances(
                      members: resolvedMembers,
                      expenses: expenses,
                      settlements: settlements,
                    );
                    final totalSpent = expenses.fold<int>(0, (s, e) => s + e.amount);

                    final otherMember = resolvedMembers.firstWhere((m) => m.id != _currentUserId, orElse: () => resolvedMembers.first);
                    final titleName = _group.isNonGroup ? otherMember.name : _group.name;

                    final myGroupBalance = balances[_currentUserId] ?? 0;

                    return Scaffold(
                      appBar: AppBar(
                        title: _isSearching 
                          ? TextField(
                              controller: _searchController,
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: 'Search expenses...',
                                border: InputBorder.none,
                                hintStyle: TextStyle(color: Colors.white30),
                              ),
                              style: const TextStyle(color: Colors.white),
                              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                            )
                          : Text(titleName),
                        actions: [
                          if (_isSearching)
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _isSearching = false;
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.close),
                            )
                          else
                            IconButton(
                              onPressed: () => setState(() => _isSearching = true),
                              icon: const Icon(Icons.search),
                            ),
                          IconButton(
                            onPressed: () => _openAnalytics(appState, expenses),
                            icon: const Icon(Icons.bar_chart_outlined),
                            tooltip: 'Analytics',
                          ),
                          if (!_group.isNonGroup)
                            IconButton(
                              onPressed: () => _openEditGroup(appState, expenses, settlements),
                              icon: const Icon(Icons.settings_outlined),
                              tooltip: 'Group Settings',
                            ),
                          IconButton(
                            onPressed: transactions.isEmpty ? null : () => _share(transactions),
                            icon: const Icon(Icons.share_outlined),
                          ),
                        ],
                      ),
                      floatingActionButton: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FloatingActionButton.extended(
                          onPressed: () => _openAddEditExpense(appState, resolvedMembers),
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('Add Expense'),
                          elevation: 4,
                        ),
                      ),
                      body: SafeArea(
                        child: AppBackdrop(
                          child: Column(
                            children: [
                              // ── Group Dashboard Summary ────────────────
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                                child: AppSurface(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                myGroupBalance == 0
                                                    ? 'You are settled up'
                                                    : myGroupBalance > 0
                                                        ? 'You are owed'
                                                        : 'You owe',
                                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '₹${myGroupBalance.abs()}',
                                                style: TextStyle(
                                                  fontSize: 32,
                                                  fontWeight: FontWeight.w900,
                                                  color: myGroupBalance == 0
                                                      ? Colors.white
                                                      : myGroupBalance > 0
                                                          ? const Color(0xFF4ADE80)
                                                          : Colors.redAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (!_group.isNonGroup)
                                            MetricPill(
                                              label: 'Total Spent',
                                              value: '₹$totalSpent',
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: () => _openSettleSheet(context, appState, transactions, memberMap),
                                              icon: const Icon(Icons.handshake_outlined),
                                              label: const Text('Settle Up'),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: kAccent,
                                                foregroundColor: Colors.black,
                                                minimumSize: const Size.fromHeight(48),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              ),
                                            ),
                                          ),
                                          if (!_group.isNonGroup) ...[
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () => _openBalancesSheet(context, balances, transactions, resolvedMembers),
                                                icon: const Icon(Icons.account_balance_wallet_outlined),
                                                label: const Text('Balances'),
                                                style: OutlinedButton.styleFrom(
                                                  minimumSize: const Size.fromHeight(48),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              Expanded(
                                child: _ActivityTab(
                                  expenses: _searchQuery.isEmpty 
                                    ? expenses 
                                    : expenses.where((e) => e.description.toLowerCase().contains(_searchQuery)).toList(),
                                  settlements: settlements,
                                  resolvedMembers: resolvedMembers,
                                  onEditExpense: (e) => _openAddEditExpense(appState, resolvedMembers, initialExpense: e),
                                  appState: appState,
                                  groupId: _group.id,
                                  totalSpent: totalSpent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text('Synchronization Issue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(error?.toString() ?? 'Something went wrong while syncing with the database.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
  }
}


// ─── Split modes ─────────────────────────────────────────────────────────

enum SplitMode {
  equal,
  exact,
  percentage,
  shares;

  String get label {
    switch (this) {
      case SplitMode.equal:
        return 'Equal';
      case SplitMode.exact:
        return 'Exact';
      case SplitMode.percentage:
        return 'Percent';
      case SplitMode.shares:
        return 'Shares';
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Tab 1: Activity (expenses + settlements in chronological order)
// ═════════════════════════════════════════════════════════════════════════

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.expenses,
    required this.settlements,
    required this.resolvedMembers,
    required this.appState,
    required this.groupId,
    required this.totalSpent,
    required this.onEditExpense,
  });

  final List<Expense> expenses;
  final List<SettlementRecord> settlements;
  final List<GroupMember> resolvedMembers;
  final AppState appState;
  final String groupId;
  final int totalSpent;
  final Function(Expense) onEditExpense;

  @override
  Widget build(BuildContext context) {
    final memberMap = {for (final m in resolvedMembers) m.id: m};

    // Merge expenses + settlements into a single chronological list.
    final rawItems = <_ActivityItem>[
      ...expenses.map((e) => _ActivityItem(
            type: _ActivityType.expense,
            date: e.createdAt,
            expense: e,
          )),
      ...settlements.map((s) => _ActivityItem(
            type: _ActivityType.settlement,
            date: s.settledAt,
            settlement: s,
          )),
    ]..sort((a, b) => b.date.compareTo(a.date));

    // Helper for confirmation
    Future<void> _showConfirmDelete(BuildContext context, String title, String body, VoidCallback onConfirm) async {
       final confirmed = await showDialog<bool>(
         context: context,
         builder: (ctx) => Center(
           child: Padding(
             padding: const EdgeInsets.all(24.0),
             child: AppSurface(
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40),
                   const SizedBox(height: 16),
                   Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                   const SizedBox(height: 12),
                   Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                   const SizedBox(height: 24),
                   Row(
                     children: [
                       Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                       const SizedBox(width: 12),
                       Expanded(child: FilledButton(
                         onPressed: () => Navigator.pop(ctx, true), 
                         style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                         child: const Text('Delete'),
                       )),
                     ],
                   )
                 ],
               ),
             ),
           ),
         ),
       );
       if (confirmed == true) onConfirm();
    }

    // Group items by month
    final groupedItems = <String, List<_ActivityItem>>{};
    for (final item in rawItems) {
      final monthStr = _formatMonthYear(item.date);
      groupedItems.putIfAbsent(monthStr, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
      children: [
        if (rawItems.isEmpty)
          const AppSurface(
            child: Text(
              'No activity yet. Add an expense or settle up to see things here.',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
          )
        else
          ...groupedItems.entries.expand((group) => [
                _MonthHeader(title: group.key),
                ...group.value.map((item) {
                  if (item.type == _ActivityType.expense) {
                    final expense = item.expense!;
                    return _ExpenseActivityCard(
                      expense: expense,
                      memberMap: memberMap,
                      onDelete: () => _showConfirmDelete(
                        context,
                        'Delete Expense',
                        'Are you sure you want to remove "${expense.description}"?',
                        () => appState.deleteExpense(groupId: groupId, expense: expense),
                      ),
                      onEdit: () => onEditExpense(expense),
                    );
                  } else {
                    final settlement = item.settlement!;
                    return _SettlementActivityCard(
                      settlement: settlement,
                      groupId: groupId,
                      appState: appState,
                      memberMap: memberMap,
                      onDelete: () => _showConfirmDelete(
                        context,
                        'Delete Settlement',
                        'Are you sure you want to remove this payment of ₹${settlement.amount}?',
                        () => appState.deleteSettlement(groupId: groupId, record: settlement),
                      ),
                    );
                  }
                }),
              ]),
      ],
    );
  }

}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white30,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─── Expense activity card (expandable) ──────────────────────────────────

class _ExpenseActivityCard extends StatefulWidget {
  const _ExpenseActivityCard({
    required this.expense,
    required this.memberMap,
    required this.onDelete,
    required this.onEdit,
  });

  final Expense expense;
  final Map<String, GroupMember> memberMap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_ExpenseActivityCard> createState() => _ExpenseActivityCardState();
}

class _ExpenseActivityCardState extends State<_ExpenseActivityCard> {
  bool _expanded = false;


  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final payer = widget.memberMap[widget.expense.payerId];
    final payerName = payer != null ? appState.resolveMemberName(payer) : 'Unknown';
    final involvedMembers = widget.expense.shares.entries
        .where((e) => e.value > 0)
        .map((e) => widget.memberMap[e.key])
        .where((m) => m != null)
        .toList();
    final cat = widget.expense.resolvedCategory;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Date Box
                    Container(
                      width: 44,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _getMonth(widget.expense.createdAt),
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white38),
                          ),
                          Text(
                            widget.expense.createdAt.day.toString(),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.expense.description,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                              payer?.id == FirebaseAuth.instance.currentUser?.uid
                                 ? 'You paid ₹${widget.expense.amount}'
                                 : '$payerName paid ₹${widget.expense.amount}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(cat.icon, color: kAccent, size: 16),
                    ),
                  ],
                ),
              ),

              // ── Involved avatars (always visible) ─────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    // Stacked avatar circles
                    SizedBox(
                      height: 24,
                      width: (involvedMembers.length * 16.0).clamp(24, 100) + 8,
                      child: Stack(
                        children: [
                          for (var i = 0; i < involvedMembers.length && i < 5; i++)
                            Positioned(
                              left: i * 14.0,
                              child: _MiniAvatar(name: involvedMembers[i]!.name),
                            ),
                          if (involvedMembers.length > 5)
                            Positioned(
                              left: 5 * 14.0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white10,
                                  border: Border.all(color: const Color(0xFF1A1927), width: 1.5),
                                ),
                                child: Center(
                                  child: Text(
                                    '+${involvedMembers.length - 5}',
                                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Split between ${involvedMembers.length}',
                      style: const TextStyle(color: Colors.white24, fontSize: 11),
                    ),
                    const Spacer(),
                    if (_expanded) ...[
                      IconButton(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16, color: kAccent),
                        style: IconButton.styleFrom(
                          backgroundColor: kAccent.withValues(alpha: 0.1),
                          minimumSize: const Size(32, 32),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                          minimumSize: const Size(32, 32),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Expanded details ──────────────────────────
              if (_expanded) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Share Breakdown',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...widget.expense.shares.entries
                          .where((e) => e.value > 0)
                          .map((entry) {
                        final member =
                            widget.memberMap[entry.key];
                        final memberName =
                            member?.name ?? entry.key;
                        final isPayer =
                            entry.key == widget.expense.payerId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              _MiniAvatar(name: memberName),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  memberName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isPayer
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (isPayer)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  margin:
                                      const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: kAccent.withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Paid',
                                    style: TextStyle(
                                        color: kAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              Text(
                                '₹${entry.value}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Settlement activity card ────────────────────────────────────────────

class _SettlementActivityCard extends StatelessWidget {
  const _SettlementActivityCard({
    required this.settlement,
    required this.groupId,
    required this.appState,
    required this.memberMap,
    required this.onDelete,
  });

  final SettlementRecord settlement;
  final String groupId;
  final AppState appState;
  final Map<String, GroupMember> memberMap;
  final VoidCallback onDelete;


  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isReceiver = settlement.toMemberId == currentUid;
    final isSender = settlement.fromMemberId == currentUid;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (settlement.status) {
      case SettlementStatus.confirmed:
        statusColor = const Color(0xFF4ADE80);
        statusIcon = Icons.check_circle_outline;
        statusText = 'Settled';
        break;
      case SettlementStatus.disputed:
        statusColor = Colors.redAccent;
        statusIcon = Icons.report_problem_outlined;
        statusText = 'Disputed';
        break;
      case SettlementStatus.pending:
      default:
        statusColor = Colors.amberAccent;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Pending';
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppSurface(
        padding: const EdgeInsets.only(top: 12, bottom: 8, left: 16, right: 16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: statusColor.withValues(alpha: 0.12),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${memberMap[settlement.fromMemberId]?.name ?? settlement.fromName} → ${memberMap[settlement.toMemberId]?.name ?? settlement.toName}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (settlement.status != SettlementStatus.confirmed) ...[
                             _statusBadge(statusText, statusColor),
                             const SizedBox(width: 6),
                          ],
                          Text(
                            '${settlement.note ?? "Payment recorded"} · ${_formatDate(settlement.settledAt)}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${settlement.amount}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.delete_outline, size: 16, color: Colors.white24),
                ),
              ],
            ),
            
            // Action buttons for the Receiver if Pending/Disputed
            if (isReceiver && settlement.status != SettlementStatus.confirmed) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.white10),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => appState.disputeSettlement(groupId: groupId, settlementId: settlement.id),
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('Dispute'),
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent, visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => appState.confirmSettlement(groupId: groupId, record: settlement),
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Confirm Receipt'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4ADE80), 
                      foregroundColor: Colors.black,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ],
              ),
            ] else if (isSender && settlement.status == SettlementStatus.pending) ...[
               const SizedBox(height: 8),
               Text(
                 'Awaiting confirmation from ${settlement.toName}',
                 style: const TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
               ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900),
      ),
    );
  }
}

// ─── Mini avatar ─────────────────────────────────────────────────────────

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kAccent.withValues(alpha: 0.15),
        border: Border.all(color: const Color(0xFF1A1927), width: 2),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: kAccent),
        ),
      ),
    );
  }
}

enum _ActivityType { expense, settlement }

class _ActivityItem {
  _ActivityItem({
    required this.type,
    required this.date,
    this.expense,
    this.settlement,
  });

  final _ActivityType type;
  final DateTime date;
  final Expense? expense;
  final SettlementRecord? settlement;
}

// ═════════════════════════════════════════════════════════════════════════
// Tab 2: Balances
// ═════════════════════════════════════════════════════════════════════════

class _BalancesTab extends StatelessWidget {
  const _BalancesTab({
    required this.resolvedMembers,
    required this.balances,
    required this.currentUserId,
    required this.transactions,
  });

  final List<GroupMember> resolvedMembers;
  final Map<String, int> balances;
  final String currentUserId;
  final List<SettlementTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final myBalance = balances[currentUserId] ?? 0;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        // ── Your summary ─────────────────────────────────────
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                myBalance == 0
                    ? 'You\'re all settled up! 🎉'
                    : myBalance > 0
                        ? 'You are owed'
                        : 'You owe',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (myBalance != 0) ...[
                const SizedBox(height: 6),
                Text(
                  '₹${myBalance.abs()}',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: myBalance > 0
                            ? const Color(0xFF4ADE80)
                            : Colors.redAccent,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  myBalance > 0
                      ? 'Overall, you get back this amount from the group.'
                      : 'Overall, you need to pay this amount to settle up.',
                  style: const TextStyle(color: Colors.white54, height: 1.4),
                ),
              ],
            ],
          ),
        ),

        // ── Per-member balances ──────────────────────────────
        const SizedBox(height: 20),
        const SectionHeading(
          title: 'Member Balances',
          subtitle: 'Net position of each member across all expenses and settlements.',
        ),
        const SizedBox(height: 12),

        ...resolvedMembers.map((member) {
          final balance = balances[member.id] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppSurface(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: balance == 0
                          ? Colors.white.withValues(alpha: 0.06)
                          : balance > 0
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.12)
                              : Colors.redAccent.withValues(alpha: 0.12),
                    ),
                    child: Center(
                      child: Text(
                        appState.resolveMemberName(member).isNotEmpty ? appState.resolveMemberName(member)[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: balance == 0
                              ? Colors.white54
                              : balance > 0
                                  ? const Color(0xFF4ADE80)
                                  : Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appState.resolveMemberName(member),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          balance == 0
                              ? 'Settled'
                              : balance > 0
                                  ? 'Gets back'
                                  : 'Owes',
                          style: TextStyle(
                            color: balance == 0
                                ? Colors.white38
                                : balance > 0
                                    ? const Color(0xFF4ADE80)
                                    : Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    balance == 0 ? '₹0' : '₹${balance.abs()}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: balance == 0
                              ? Colors.white38
                              : balance > 0
                                  ? const Color(0xFF4ADE80)
                                  : Colors.redAccent,
                        ),
                  ),
                ],
              ),
            ),
          );
        }),

        // ── Pairwise breakdown ────────────────────────────────
        if (transactions.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeading(
            title: 'Who Pays Whom',
            subtitle: 'Simplified pairwise transfers to settle all balances.',
          ),
          const SizedBox(height: 12),
          ...transactions.map((t) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppSurface(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_forward_rounded, color: kAccent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${t.fromName} → ${t.toName}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '₹${t.amount}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: kAccent,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Tab 3: Settle (transaction cards with UPI + record payment)
// ═════════════════════════════════════════════════════════════════════════

class _SettleTab extends StatelessWidget {
  const _SettleTab({
    required this.transactions,
    required this.currentUserId,
    required this.memberMap,
    required this.onPay,
    required this.onRecord,
    required this.onRemind,
  });

  final List<SettlementTransaction> transactions;
  final String currentUserId;
  final Map<String, GroupMember> memberMap;
  final Future<void> Function(SettlementTransaction) onPay;
  final Future<void> Function(SettlementTransaction) onRecord;
  final Future<void> Function(SettlementTransaction) onRemind;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        const SectionHeading(
          title: 'Settle Up',
          subtitle: 'Pay via UPI or record a manual payment to clear balances.',
        ),
        const SizedBox(height: 16),
        if (transactions.isEmpty)
          const AppSurface(
            child: Column(
              children: [
                Icon(Icons.celebration_outlined, color: kAccent, size: 36),
                SizedBox(height: 12),
                Text(
                  'All settled! 🎉',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                SizedBox(height: 6),
                Text(
                  'No pending transfers. Everyone is even.',
                  style: TextStyle(color: Colors.white54, height: 1.4),
                ),
              ],
            ),
          )
        else
          ...transactions.map(
            (transaction) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _TransactionCard(
                transaction: transaction,
                currentUserId: currentUserId,
                onPay: () => onPay(transaction),
                onRecord: () => onRecord(transaction),
                onRemind: () => onRemind(transaction),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Transaction card ────────────────────────────────────────────────────

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.transaction,
    required this.currentUserId,
    required this.onPay,
    required this.onRecord,
    required this.onRemind,
  });

  final SettlementTransaction transaction;
  final String currentUserId;
  final VoidCallback onPay;
  final VoidCallback onRecord;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) {
    final isCurrentUserDebtor = transaction.fromMemberId == currentUserId;
    final isCurrentUserCreditor = transaction.toMemberId == currentUserId;
    final canPay = transaction.payeeUpiId != null && isCurrentUserDebtor;

    final qrData = canPay
        ? generateUpiLink(
            upiId: transaction.payeeUpiId!,
            payeeName: transaction.toName,
            amount: transaction.amount,
          )
        : null;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${transaction.fromName} → ${transaction.toName}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '₹${transaction.amount}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: kAccent,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status text
          if (isCurrentUserCreditor)
            const Text('You receive this payment — sit tight!', style: TextStyle(color: kSecondary))
          else if (isCurrentUserDebtor && canPay)
            Text('Pay ${transaction.toName} directly via UPI', style: const TextStyle(color: Colors.white70))
          else if (isCurrentUserDebtor && transaction.payeeUpiId == null)
            Text('No UPI ID saved for ${transaction.toName} yet', style: const TextStyle(color: Colors.white70))
          else
            Text('${transaction.fromName} pays ${transaction.toName}', style: const TextStyle(color: Colors.white70)),

          // Creditor specific: WhatsApp Nudge
          if (isCurrentUserCreditor && transaction.payerPhoneNumber != null && transaction.payerPhoneNumber!.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRemind,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Send WhatsApp Reminder'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],

          // QR + Pay Now (only when current user owes + UPI available)
          if (qrData != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: QrImageView(data: qrData, size: 180, backgroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPay,
                child: const Text('Pay Now'),
              ),
            ),
          ] else if (isCurrentUserDebtor && transaction.payeeUpiId == null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: null,
                child: const Text('UPI Missing'),
              ),
            ),
          ],

          // Record payment button — always visible
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRecord,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Record Payment'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Analytics Dashboard ──────────────────────────────────────────────────

class _AnalyticsSheet extends StatelessWidget {
  const _AnalyticsSheet({
    required this.expenses,
    required this.group,
  });

  final List<Expense> expenses;
  final SettlementGroup group;

  Map<ExpenseCategory, int> _computeTotals() {
    final totals = <ExpenseCategory, int>{};
    for (final e in expenses) {
      final cat = e.resolvedCategory;
      totals[cat] = (totals[cat] ?? 0) + e.amount;
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final totals = _computeTotals();
    final sortedCats = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final grandTotal = totals.values.fold<int>(0, (sum, v) => sum + v);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF13121D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.all(24),
              child: SectionHeading(
                title: 'Spending Analytics',
                subtitle: 'Category-wise breakdown of all expenses.',
              ),
            ),
            if (expenses.isEmpty)
              const Expanded(child: Center(child: Text('No expenses recorded yet', style: TextStyle(color: Colors.white38))))
            else
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: sortedCats.length,
                  itemBuilder: (context, index) {
                    final entry = sortedCats[index];
                    final cat = entry.key;
                    final amount = entry.value;
                    final pct = amount / grandTotal;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(cat.icon, size: 18, color: kAccent),
                              const SizedBox(width: 12),
                              Expanded(child: Text(cat.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text('₹$amount', style: const TextStyle(fontWeight: FontWeight.w800, color: kAccent)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Stack(
                            children: [
                              Container(
                                height: 6,
                                width: double.infinity,
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(3)),
                              ),
                              FractionallySizedBox(
                                widthFactor: pct,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(gradient: LinearGradient(colors: [kAccent, kSecondary]), borderRadius: BorderRadius.circular(3)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
