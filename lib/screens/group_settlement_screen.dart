import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../models/activity_log.dart';
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
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    
    // Sync current user's info into the group document (UPI ID, name updates, etc.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().syncMemberInfo(_group.id, widget.profile);
    });
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

  void _openSettleSheet(
    BuildContext context,
    AppState appState,
    List<SettlementTransaction> transactions,
    Map<String, GroupMember> memberMap,
    List<GroupMember> resolvedMembers, {
    required String currentMemberId,
  }) {
     showModalBottomSheet<void>(
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
       useSafeArea: true,
       builder: (c) => Container(
         decoration: const BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
         ),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             const SizedBox(height: 12),
             Container(
               height: 5,
               width: 40,
               decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
             ),
             const SizedBox(height: 12),
             Flexible(
               child: _SettleTab(
                  memberMap: memberMap,
                 transactions: transactions,
                 currentUserId: currentMemberId,
                onPay: (t) => _launchUpi(t, appState),
                 onRecord: (t) => _openRecordSettlement(appState, t, resolvedMembers),
                 onRemind: _sendWhatsappReminder,
               ),
             ),
           ],
         ),
       ),
     );
  }

  void _openBalancesSheet(
    BuildContext context,
    Map<String, double> balances,
    List<SettlementTransaction> transactions,
    List<GroupMember> resolvedMembers, {
    required String currentMemberId,
  }) {
     showModalBottomSheet<void>(
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
       useSafeArea: true,
       builder: (c) => Container(
         decoration: const BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
         ),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             const SizedBox(height: 8),
             Container(
               height: 5,
               width: 40,
               decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
             ),
             const SizedBox(height: 16),
             Flexible(
               child: _BalancesTab(
                 resolvedMembers: resolvedMembers,
                 balances: balances,
                 currentUserId: currentMemberId,
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
    final List<GroupMember> resolved = groupMembers.map<GroupMember>((member) {
      // Try to find live profile by UID first, then by ID, then by normalized phone number
      UserProfile? live = liveProfiles[member.uid ?? ''];
      if (live == null) live = liveProfiles[member.id];
      if (live == null && member.phoneNumber != null) {
        live = liveProfiles[AppState.normalisePhone(member.phoneNumber!)];
      }

      final GroupMember baseMember = live == null 
        ? member 
        : member.copyWith(
            name: live.displayName,
            upiId: live.upiId,
            phoneNumber: live.phoneNumber,
            uid: live.uid,
            photoUrl: live.photoUrl,
          );
      
      return baseMember.copyWith(
        name: appState.resolveMemberName(baseMember),
        isSelf: baseMember.id == _currentUserId || (baseMember.uid != null && baseMember.uid == _currentUserId),
      );
    }).toList();
    return resolved;
  }

  String get _currentUserId => widget.profile.uid;

  /// Expenses/settlements are keyed by `GroupMember.id` (group-scoped accounting id),
  /// which may be different from the Firebase Auth UID for invited/phone members.
  /// Resolve the current user's member entry within this group and return its `id`.
  String _currentMemberId(List<GroupMember> resolvedMembers) {
    final uid = widget.profile.uid;
    final rawPhone = widget.profile.phoneNumber;
    final normalisedProfilePhone =
        (rawPhone != null && rawPhone.trim().isNotEmpty)
            ? AppState.normalisePhone(rawPhone)
            : null;

    for (final m in resolvedMembers) {
      if (m.id == uid) return m.id;
      if (m.uid != null && m.uid == uid) return m.id;
      if (normalisedProfilePhone != null &&
          m.phoneNumber != null &&
          AppState.normalisePhone(m.phoneNumber!) == normalisedProfilePhone) {
        return m.id;
      }
    }

    return uid;
  }

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

      // Immersive Confirmation UI - Fintech Style
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rupee Seal
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kPrimaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: kPrimaryBlue.withValues(alpha: 0.2), width: 2),
                ),
                child: const Center(
                  child: Text('₹', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: kPrimaryBlue)),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Payment Confirmation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text(
                'Verify your bank transfer details',
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
              const SizedBox(height: 32),
              // Transaction Details Card
              AppSurface(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Amount to Pay', style: TextStyle(color: Colors.black38, fontSize: 13)),
                        Text('₹${formatAmount(transaction.amount)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: kPrimaryBlue)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(color: Colors.black12),
                    ),
                    Row(
                      children: [
                        const Text('Paying to: ', style: TextStyle(color: Colors.black38, fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            transaction.toName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kDarkBlue),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'By clicking "Confirm & Record", you acknowledge that the funds have been transferred in your UPI app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black12, fontSize: 11, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black38,
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: const Text('Did not pay', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimaryBlue,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Confirm & Record', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
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
    
    final message = "Hey ${transaction.fromName}, just a quick remind to settle up ₹${formatAmount(transaction.amount)} for '${_group.name}' on Bharat Dues! ${transaction.payeeUpiId != null ? 'My UPI is ${transaction.payeeUpiId}. ' : ''}Thanks 💸";
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
              final total = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
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
                  final mults = <String, double>{};
                  for (final m in includedMembers) {
                    mults[m.id] = double.tryParse(multControllers[m.id]!.text.trim()) ?? 1.0;
                  }
                  final shares = buildMultiplierShareMap(total: total, members: includedMembers, multipliers: mults);
                  for (final m in resolvedMembers) {
                    shareControllers[m.id]!.text = formatAmount(shares[m.id] ?? 0.0);
                  }
                case SplitMode.exact:
                  break; 
              }
              // Force rebuild so the 'diff' and 'sumOfShares' reflect the new calculation
              setSheetState(() {});
            }

            if (splitMode != SplitMode.exact) {
              recomputeShares();
            }

            final totalExpense = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
            final sumOfShares = shareControllers.values.fold<double>(0, (sum, ctrl) => sum + (double.tryParse(ctrl.text.trim()) ?? 0.0));
            final isBalanced = (totalExpense - sumOfShares).abs() < 0.01;
            final diff = totalExpense - sumOfShares;
            
            final sumOfPcts = pctControllers.entries
                .where((e) => includedIds.contains(e.key))
                .fold<double>(0, (sum, e) => sum + (double.tryParse(e.value.text.trim()) ?? 0));
            final diffPct = 100.0 - sumOfPcts;

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
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                            const SizedBox(height: 20),
                      TextFormField(
                        controller: descCtrl,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                                avatar: Icon(cat.icon, size: 14, color: isSelected ? Colors.black : Colors.black87),
                                label: Text(cat.label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? Colors.black : Colors.black87)),
                                selected: isSelected,
                                onSelected: (_) => setSheetState(() {
                                  selectedCategory = cat;
                                  isCategoryManual = true;
                                }),
                                selectedColor: kPrimaryBlue,
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
                          color: Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                        ),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: kPrimaryBlue),
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
                                final val = double.tryParse((v ?? '').trim());
                                return (val == null || val <= 0) ? '!' : null;
                              },
                            ),
                            const Divider(height: 32, color: Colors.black12),
                            DropdownButtonFormField<String>(
                              initialValue: payerId,
                              dropdownColor: Colors.white,
                              decoration: const InputDecoration(
                                labelText: 'Paid By',
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              items: resolvedMembers
                                  .map((m) => DropdownMenuItem(value: m.id, child: Text(appState.resolveMemberName(m), style: const TextStyle(fontWeight: FontWeight.w700))))
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
                          const Text('SPLIT METHOD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black38, letterSpacing: 1.5)),
                          Text(splitMode.label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kPrimaryBlue)),
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
                                label: Text(m.label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? Colors.black : Colors.black87)),
                                selected: isSelected,
                                onSelected: (val) {
                                  if (val) {
                                    setSheetState(() {
                                      splitMode = m;
                                      recomputeShares();
                                    });
                                  }
                                },
                                selectedColor: kPrimaryBlue,
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
                            border: Border.all(color: isIncluded ? kPrimaryBlue.withValues(alpha: 0.1) : Colors.transparent),
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
                                    color: isIncluded ? kPrimaryBlue : Colors.black12,
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
                                            fontWeight: isIncluded ? FontWeight.w600 : FontWeight.w500,
                                            color: isIncluded ? kDarkBlue : Colors.black38,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (isIncluded && (splitMode == SplitMode.percentage || splitMode == SplitMode.shares))
                                          Text(
                                            splitMode == SplitMode.percentage 
                                              ? '${pctControllers[m.id]!.text}% Share'
                                              : '${multControllers[m.id]!.text}x Weight',
                                            style: const TextStyle(fontSize: 10, color: kPrimaryBlue, fontWeight: FontWeight.w700),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isIncluded && (splitMode == SplitMode.percentage || splitMode == SplitMode.shares)) ...[
                                    SizedBox(
                                      width: 45,
                                      child: TextFormField(
                                        controller: splitMode == SplitMode.percentage ? pctControllers[m.id] : multControllers[m.id],
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        decoration: InputDecoration(
                                          hintText: splitMode == SplitMode.percentage ? '%' : 'x',
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                          border: UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryBlue.withValues(alpha: 0.3))),
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
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                      enabled: isIncluded && splitMode == SplitMode.exact,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 16, 
                                        fontWeight: FontWeight.w700, 
                                        color: isIncluded ? kDarkBlue : Colors.black12
                                      ),
                                      decoration: InputDecoration(
                                        prefixText: '₹ ',
                                        prefixStyle: const TextStyle(fontSize: 11, color: Colors.black38),
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
                          color: isBalanced ? kPrimaryBlue.withValues(alpha: 0.1) : Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
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
                                      color: isBalanced ? kPrimaryBlue : Colors.redAccent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  Text(
                                    isBalanced 
                                      ? 'All shares match total' 
                                      : (splitMode == SplitMode.percentage 
                                          ? 'Remaining: ${diffPct.toStringAsFixed(1)}%' 
                                          : 'Remaining: ₹${formatAmount(diff)}'),
                                    style: TextStyle(
                                      color: isBalanced ? kDarkBlue : Colors.redAccent,
                                      fontWeight: FontWeight.w600,
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
                                final currentTotal = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                                final currentSum = shareControllers.values.fold<double>(0, (sum, ctrl) => sum + (double.tryParse(ctrl.text.trim()) ?? 0.0));
                                
                                if ((currentTotal - currentSum).abs() >= 0.01) {
                                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: Colors.redAccent,
                                      content: Text('Total (₹${formatAmount(currentTotal)}) ≠ Shares (₹${formatAmount(currentSum)})', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  );
                                  return;
                                }

                                final shares = { for (final m in resolvedMembers) m.id: double.tryParse(shareControllers[m.id]!.text.trim()) ?? 0.0 };
                                
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
    List<GroupMember> resolvedMembers,
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                      validator: (v) {
                        final val = double.tryParse((v ?? '').trim());
                        if (val == null || val <= 0) return 'Enter a valid amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(labelText: 'Note (optional)'),
                    ),
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
                            amount: double.parse(amountCtrl.text.trim()),
                            settledAt: DateTime.now(),
                            createdBy: widget.profile.uid,
                            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                          );

                          final myMemberId = _currentMemberId(resolvedMembers);
                          final isReceiver = transaction.toMemberId == myMemberId;
                          
                          await appState.addSettlement(
                            groupId: _group.id, 
                            record: record,
                            confirmed: isReceiver,
                          );
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        },
                        child: Text(transaction.toMemberId == _currentMemberId(resolvedMembers) ? 'Confirm Receipt' : 'Record Payment'),
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
          stream: appState.profilesStream([
            ..._group.members.map((m) => m.id),
            ..._group.members.where((m) => m.phoneNumber != null).map((m) => m.phoneNumber!),
          ]),
          builder: (context, profilesSnap) {
            final profiles = profilesSnap.data ?? {};
            final resolvedMembers = _resolveAll(_group.members, profiles);
            final currentMemberId = _currentMemberId(resolvedMembers);
            
            // Build a smart member map that can resolve both by primary ID and secondary UID
            final memberMap = <String, GroupMember>{};
            for (var m in resolvedMembers) {
              memberMap[m.id] = m;
              if (m.uid != null) memberMap[m.uid!] = m;
            }

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
                    final totalSpent = expenses.fold<double>(0, (s, e) => s + e.amount);

                    final otherMember = resolvedMembers.firstWhere(
                      (m) => m.id != currentMemberId,
                      orElse: () => resolvedMembers.first,
                    );
                    final titleName = _group.isNonGroup ? otherMember.name : _group.name;

                    final myGroupBalance = balances[currentMemberId] ?? 0.0;

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
                            : Row(
                                children: [
                                  Image.asset('assets/images/logo.png', height: 24),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(titleName, overflow: TextOverflow.ellipsis)),
                                ],
                              ),
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
                      body: Column(
                        children: [
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
                                            style: const TextStyle(color: Colors.black45, fontSize: 13),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '₹${formatAmount(myGroupBalance.abs())}',
                                            style: TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.w700,
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
                                          value: '₹${formatAmount(totalSpent)}',
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                            onPressed: () => _openSettleSheet(
                                              context,
                                              appState,
                                              transactions,
                                              memberMap,
                                              resolvedMembers,
                                              currentMemberId: currentMemberId,
                                            ),
                                          icon: const Icon(Icons.handshake_outlined),
                                          label: const Text('Bharat Dues Summary'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: kPrimaryBlue,
                                            foregroundColor: Colors.black,
                                            minimumSize: const Size.fromHeight(48),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: DefaultTabController(
                              length: 3,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                    child: Container(
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: TabBar(
                                        isScrollable: false,
                                        tabAlignment: TabAlignment.fill,
                                        dividerColor: Colors.transparent,
                                        indicator: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          color: kPrimaryBlue,
                                        ),
                                        indicatorSize: TabBarIndicatorSize.tab,
                                        labelColor: Colors.black,
                                        unselectedLabelColor: Colors.black38,
                                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1),
                                        tabs: const [
                                          Tab(text: 'EXPENSES'),
                                          Tab(text: 'ACTIVITY'),
                                          Tab(text: 'BALANCES'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      children: [
                                        _ExpensesTab(
                                          expenses: _searchQuery.isEmpty 
                                            ? expenses 
                                            : expenses.where((e) => e.description.toLowerCase().contains(_searchQuery)).toList(),
                                          settlements: settlements,
                                          resolvedMembers: resolvedMembers,
                                          onEditExpense: (e) => _openAddEditExpense(appState, resolvedMembers, initialExpense: e),
                                          appState: appState,
                                          groupId: _group.id,
                                        ),
                                        _ActivityLogTab(
                                          groupId: _group.id,
                                        ),
                                        _BalancesTab(
                                          resolvedMembers: resolvedMembers,
                                          balances: Map<String, double>.from(balances),
                                          currentUserId: currentMemberId,
                                          transactions: transactions,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      floatingActionButton: FloatingActionButton.extended(
                        onPressed: () => _openAddEditExpense(appState, resolvedMembers),
                        icon: const Icon(Icons.add_rounded, size: 28),
                        label: const Text('Expense'),
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
              Text(error?.toString() ?? 'Something went wrong while syncing with the database.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black45)),
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

class _ExpensesTab extends StatelessWidget {
  const _ExpensesTab({
    required this.expenses,
    required this.settlements,
    required this.resolvedMembers,
    required this.appState,
    required this.groupId,
    required this.onEditExpense,
  });

  final List<Expense> expenses;
  final List<SettlementRecord> settlements;
  final List<GroupMember> resolvedMembers;
  final AppState appState;
  final String groupId;
  final Function(Expense) onEditExpense;

  @override
  Widget build(BuildContext context) {
    final memberMap = <String, GroupMember>{};
    for (var m in resolvedMembers) {
      memberMap[m.id] = m;
      if (m.uid != null) memberMap[m.uid!] = m;
    }

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
    Future<void> showConfirmDelete(BuildContext context, String title, String body, VoidCallback onConfirm) async {
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
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
                    const SizedBox(height: 12),
                    Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87)),
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
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                'No records yet. Add an expense or settle up to see things here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black38, height: 1.5),
              ),
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
                      onDelete: () => showConfirmDelete(
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
                      onDelete: () => showConfirmDelete(
                        context,
                        'Delete Settlement',
                        'Are you sure you want to remove this payment of ₹${formatAmount(settlement.amount)}?',
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

// ═════════════════════════════════════════════════════════════════════════
// Tab 2: Activity Log (Audit history of "who did what")
// ═════════════════════════════════════════════════════════════════════════


class _ActivityLogTab extends StatelessWidget {
  const _ActivityLogTab({
    required this.groupId,
  });

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    return StreamBuilder<List<ActivityLog>>(
      stream: appState.activitiesStream(groupId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: kPrimaryBlue));
        }

        final logs = snapshot.data ?? [];

        if (logs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_outlined, color: Colors.black12, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No activities yet reported for this group.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black12),
                  ),
                ],
              ),
            ),
          );
        }

        // Group by date
        final grouped = <String, List<ActivityLog>>{};
        for (final log in logs) {
          final day = _formatDateHeader(log.timestamp);
          grouped.putIfAbsent(day, () => []).add(log);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
          children: [
            ...grouped.entries.expand((group) => [
                  _MonthHeader(title: group.key),
                  ...group.value.map((log) => _ActivityLogItem(log: log)),
                ]),
          ],
        );
      },
    );
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    return _formatMonthYear(date);
  }
}

class _ActivityLogItem extends StatelessWidget {
  const _ActivityLogItem({required this.log});
  final ActivityLog log;

  @override
  Widget build(BuildContext context) {
    final iconData = _getIconForAction(log.action);
    final color = _getColorForAction(log.action);
    final isMe = log.actorId == FirebaseAuth.instance.currentUser?.uid;
    final actor = isMe ? 'You' : log.actorName;
    
    // DETAIL GENERATION
    String details = '';
    final changes = log.changedFields;
    if (log.action == ActivityAction.expenseEdited && changes.isNotEmpty) {
      final List<String> detailParts = [];
      if (changes.contains('amount') && log.oldAmount != null) {
        detailParts.add('amount from ₹${formatAmount(log.oldAmount!)} to ₹${formatAmount(log.amount ?? 0)}');
      }
      
      final otherChanges = changes.where((c) => c != 'amount').toList();
      if (otherChanges.isNotEmpty) {
        detailParts.add('fields: ${otherChanges.join(', ')}');
      }
      
      details = ' (${detailParts.join('; ')})';
    } else if (log.action == ActivityAction.groupEdited) {
       details = ' (New name: ${log.targetName})';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MiniAvatar(
              name: log.actorName, 
              photoUrl: log.actorPhotoUrl, 
              size: 36,
            ),
            const SizedBox(width: 14),
            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          color: Colors.black87, fontSize: 13, height: 1.4),
                      children: [
                        TextSpan(
                            text: actor,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: kDarkBlue)),
                        TextSpan(text: ' ${_getActionText(log.action)} '),
                        TextSpan(
                            text: log.targetName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kDarkBlue)),
                        if (log.amount != null) ...[
                          const TextSpan(text: ' of '),
                          TextSpan(
                              text: '₹${formatAmount(log.amount ?? 0)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF00897B))),
                        ],
                        if (details.isNotEmpty)
                          TextSpan(
                            text: details,
                            style: const TextStyle(color: Colors.black38, fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(log.timestamp),
                    style: const TextStyle(color: Colors.black12, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForAction(ActivityAction action) {
    switch (action) {
      case ActivityAction.expenseAdded:
        return Icons.add_circle_outline_rounded;
      case ActivityAction.expenseEdited:
        return Icons.edit_note_rounded;
      case ActivityAction.expenseDeleted:
        return Icons.delete_outline_rounded;
      case ActivityAction.settlementRecorded:
        return Icons.account_balance_wallet_outlined;
      case ActivityAction.settlementConfirmed:
        return Icons.verified_rounded;
      case ActivityAction.settlementDisputed:
        return Icons.gpp_bad_outlined;
      case ActivityAction.groupCreated:
        return Icons.group_add_rounded;
      case ActivityAction.groupEdited:
        return Icons.settings_rounded;
      case ActivityAction.memberAdded:
        return Icons.person_add_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _getColorForAction(ActivityAction action) {
    switch (action) {
      case ActivityAction.expenseAdded:
        return const Color(0xFF63B3ED);
      case ActivityAction.expenseEdited:
        return const Color(0xFFF6AD55);
      case ActivityAction.expenseDeleted:
        return Colors.redAccent;
      case ActivityAction.settlementRecorded:
        return Colors.amber;
      case ActivityAction.settlementConfirmed:
        return const Color(0xFF00695C);
      case ActivityAction.settlementDisputed:
        return Colors.orangeAccent;
      case ActivityAction.groupCreated:
        return kPrimaryBlue;
      case ActivityAction.groupEdited:
        return Colors.black45;
      case ActivityAction.memberAdded:
        return const Color(0xFFF687B3);
      default:
        return Colors.black12;
    }
  }

  String _getActionText(ActivityAction action) {
    switch (action) {
      case ActivityAction.expenseAdded:
        return 'added';
      case ActivityAction.expenseEdited:
        return 'updated';
      case ActivityAction.expenseDeleted:
        return 'deleted';
      case ActivityAction.settlementRecorded:
        return 'recorded';
      case ActivityAction.settlementConfirmed:
        return 'confirmed';
      case ActivityAction.settlementDisputed:
        return 'disputed';
      case ActivityAction.groupCreated:
        return 'created group';
      case ActivityAction.groupEdited:
        return 'updated settings for';
      case ActivityAction.memberAdded:
        return 'added member';
      default:
        return 'performed';
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $ampm';
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
          fontWeight: FontWeight.w700,
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
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final payer = widget.memberMap[widget.expense.payerId];
    final payerName = payer != null ? appState.resolveMemberName(payer) : 'Unknown';
    final involvedMembers = widget.expense.shares.entries
        .where((e) => e.value > 0)
        .map((e) => widget.memberMap[e.key])
        .where((m) => m != null)
        .toList();
    final isMePayer = widget.expense.payerId == currentUserId || payer?.uid == currentUserId;
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
                        color: Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _getMonth(widget.expense.createdAt),
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.black38),
                          ),
                          Text(
                            widget.expense.createdAt.day.toString(),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: kDarkBlue),
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
                                fontWeight: FontWeight.w600, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                              payer?.id == FirebaseAuth.instance.currentUser?.uid
                                 ? 'You paid ₹${formatAmount(widget.expense.amount)}'
                                 : '$payerName paid ₹${formatAmount(widget.expense.amount)}',
                            style: const TextStyle(
                                color: Colors.black45, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kPrimaryBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(cat.icon, color: kPrimaryBlue, size: 16),
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
                      height: 28,
                      width: (involvedMembers.length * 18.0).clamp(28, 120) + 12,
                      child: Stack(
                        children: [
                          for (var i = 0; i < involvedMembers.length && i < 5; i++)
                            Positioned(
                              left: i * 16.0,
                              child: _MiniAvatar(
                                name: involvedMembers[i]!.name,
                                photoUrl: involvedMembers[i]!.photoUrl, 
                                size: 28,
                              ),
                            ),
                          if (involvedMembers.length > 5)
                            Positioned(
                              left: 5 * 16.0,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black12,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    '+${involvedMembers.length - 5}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${involvedMembers.length} involved',
                      style: const TextStyle(color: Colors.black12, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    if (_expanded) ...[
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: widget.onEdit,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: kPrimaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.edit_rounded, size: 16, color: kPrimaryBlue),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: widget.onDelete,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.delete_rounded, size: 16, color: Colors.redAccent),
                          ),
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
                            color: Colors.black45,
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
                            member != null ? appState.resolveMemberName(member) : entry.key;
                        final isPayer =
                            entry.key == widget.expense.payerId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              _MiniAvatar(name: memberName, photoUrl: member?.photoUrl),
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
                                    color: kPrimaryBlue.withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Paid',
                                    style: TextStyle(
                                        color: kPrimaryBlue,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              Text(
                                '₹${formatAmount(entry.value)}',
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
        statusColor = const Color(0xFF00897B); // Darker Green
        statusIcon = Icons.check_circle;
        statusText = 'Settled';
        break;
      case SettlementStatus.disputed:
        statusColor = Colors.red.shade700;
        statusIcon = Icons.report_problem;
        statusText = 'Disputed';
        break;
      case SettlementStatus.pending:
        statusColor = Colors.amber.shade700;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Pending';
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [statusColor.withValues(alpha: 0.15), statusColor.withValues(alpha: 0.05)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: statusColor.withValues(alpha: 0.2), width: 1),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${memberMap[settlement.fromMemberId]?.name ?? settlement.fromName} Paid ${memberMap[settlement.toMemberId]?.name ?? settlement.toName}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                           _statusBadge(statusText, statusColor),
                           const SizedBox(width: 8),
                           Expanded(
                             child: Text(
                               '${settlement.note ?? "Payment"} · ${_formatDate(settlement.settledAt)}',
                               style: const TextStyle(color: Colors.black38, fontSize: 11, fontWeight: FontWeight.w500),
                               maxLines: 1,
                               overflow: TextOverflow.ellipsis,
                             ),
                           ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${formatAmount(settlement.amount)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onDelete,
                      child: const Text('Delete', style: TextStyle(color: Colors.black12, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
            
            // Action buttons for the Receiver if Pending/Disputed
            if (isReceiver && settlement.status != SettlementStatus.confirmed) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),
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
                      minimumSize: Size.zero,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ] else if (isSender && settlement.status == SettlementStatus.pending) ...[
               const SizedBox(height: 8),
               Text(
                 'Awaiting confirmation from ${settlement.toName}',
                 style: const TextStyle(color: Colors.black38, fontSize: 10, fontStyle: FontStyle.italic),
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
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ─── Mini avatar ─────────────────────────────────────────────────────────

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name, this.photoUrl, this.size = 26});

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasImage = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kPrimaryBlue.withValues(alpha: 0.15),
        border: Border.all(color: const Color(0xFF1A1927), width: 2),
      ),
      child: ClipOval(
        child: hasImage 
          ? Image.network(
              photoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildInitial(),
            )
          : _buildInitial(),
      ),
    );
  }

  Widget _buildInitial() {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
            fontSize: size * 0.4, fontWeight: FontWeight.w600, color: kPrimaryBlue),
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
  final Map<String, double> balances;
  final String currentUserId;
  final List<SettlementTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final myBalance = balances[currentUserId] ?? 0.0;

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
                  '₹${formatAmount(myBalance.abs())}',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: myBalance > 0
                            ? const Color(0xFF4ADE80)
                            : Colors.redAccent,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  myBalance > 0
                      ? 'Overall, you get back this amount from the group.'
                      : 'Overall, you need to pay this amount to settle up.',
                  style: const TextStyle(color: Colors.black45, height: 1.4),
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
          final balance = balances[member.id] ?? 0.0;
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
                          fontWeight: FontWeight.w600,
                          color: balance == 0
                              ? Colors.black45
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
                                ? Colors.black38
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
                    balance == 0 ? '₹0' : '₹${formatAmount(balance.abs())}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: balance == 0
                              ? Colors.black38
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
                    const Icon(Icons.arrow_forward_rounded, color: kPrimaryBlue, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${t.fromName} → ${t.toName}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '₹${formatAmount(t.amount)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: kPrimaryBlue,
                            fontWeight: FontWeight.w600,
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
          title: 'Bharat Dues',
          subtitle: 'Pay via UPI or record a manual payment to clear balances.',
        ),
        const SizedBox(height: 16),
        if (transactions.isEmpty)
          const AppSurface(
            child: Column(
              children: [
                Icon(Icons.celebration_outlined, color: kPrimaryBlue, size: 36),
                SizedBox(height: 12),
                Text(
                  'All settled! 🎉',
                  style: TextStyle(color: kDarkBlue, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                SizedBox(height: 6),
                Text(
                  'No pending transfers. Everyone is even.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, height: 1.4),
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
                memberMap: memberMap,
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
    required this.memberMap,
  });

  final SettlementTransaction transaction;
  final String currentUserId;
  final VoidCallback onPay;
  final VoidCallback onRecord;
  final VoidCallback onRemind;
  final Map<String, GroupMember> memberMap;

  @override
  Widget build(BuildContext context) {
    final isCurrentUserDebtor = transaction.fromMemberId == currentUserId;
    final isCurrentUserCreditor = transaction.toMemberId == currentUserId;
    final hasTargetUpi = transaction.payeeUpiId != null && 
                          transaction.payeeUpiId!.trim().isNotEmpty && 
                          transaction.payeeUpiId!.contains('@');
    final canPay = hasTargetUpi && isCurrentUserDebtor;

    final qrData = canPay
        ? generateUpiLink(
            upiId: transaction.payeeUpiId!,
            payeeName: transaction.toName,
            amount: transaction.amount,
          )
        : null;

    return AppSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar Stack
              SizedBox(
                width: 70,
                child: Stack(
                  children: [
                    _MiniAvatar(
                        name: transaction.fromName, 
                        photoUrl: memberMap[transaction.fromMemberId]?.photoUrl,
                        size: 40,
                    ),
                    Positioned(
                      left: 24,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: _MiniAvatar(
                            name: transaction.toName, 
                            photoUrl: memberMap[transaction.toMemberId]?.photoUrl,
                            size: 40,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${transaction.fromName} owes ${transaction.toName}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${formatAmount(transaction.amount)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: kPrimaryBlue,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (isCurrentUserCreditor) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.handshake_outlined, color: Color(0xFF4ADE80), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You are the receiver. Once they pay, mark it as settled below or confirm their record.',
                      style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            if (transaction.payerPhoneNumber != null && transaction.payerPhoneNumber!.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRemind,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Remind on WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ] else if (isCurrentUserDebtor) ...[
            if (canPay) ...[
               const Text('GENERATE QR', style: TextStyle(color: Colors.black12, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
               const SizedBox(height: 12),
               Container(
                 width: double.infinity,
                 padding: const EdgeInsets.all(20),
                 decoration: BoxDecoration(
                   color: Colors.white,
                   borderRadius: BorderRadius.circular(16),
                 ),
                 child: Center(
                   child: QrImageView(data: qrData!, size: 160, backgroundColor: Colors.white),
                 ),
               ),
               const SizedBox(height: 16),
               SizedBox(
                 width: double.infinity,
                 child: FilledButton.icon(
                   onPressed: onPay,
                   icon: const Icon(Icons.bolt_rounded, size: 18),
                   label: const Text('Pay with UPI App'),
                   style: FilledButton.styleFrom(
                     backgroundColor: kPrimaryBlue,
                     foregroundColor: Colors.black,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                   ),
                 ),
               ),
            ] else ...[
               Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: Colors.amberAccent.withValues(alpha: 0.1),
                   borderRadius: BorderRadius.circular(12),
                 ),
                 child: Row(
                   children: [
                     const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 16),
                     const SizedBox(width: 8),
                     Expanded(
                       child: Text(
                         '${transaction.toName} has not added a UPI ID yet. You can still record a manual payment.',
                         style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                       ),
                     ),
                   ],
                 ),
               ),
            ],
          ],

          // Record payment button
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onRecord,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Text('Record Manual Payment', style: TextStyle(color: Colors.black45, fontSize: 12)),
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

  Map<ExpenseCategory, double> _computeTotals() {
    final totals = <ExpenseCategory, double>{};
    for (final e in expenses) {
      final cat = e.resolvedCategory;
      totals[cat] = (totals[cat] ?? 0.0) + e.amount;
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final totals = _computeTotals();
    final sortedCats = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final grandTotal = totals.values.fold<double>(0, (sum, v) => sum + v);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.all(24),
              child: SectionHeading(
                title: 'Spending Analytics',
                subtitle: 'Category-wise breakdown of all expenses.',
              ),
            ),
            if (expenses.isEmpty)
              const Expanded(child: Center(child: Text('No expenses recorded yet', style: TextStyle(color: Colors.black38))))
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
                              Icon(cat.icon, size: 18, color: kPrimaryBlue),
                              const SizedBox(width: 12),
                              Expanded(child: Text(cat.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text('₹${formatAmount(amount)}', style: const TextStyle(fontWeight: FontWeight.w600, color: kPrimaryBlue)),
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
                                  decoration: BoxDecoration(gradient: LinearGradient(colors: [kPrimaryBlue, kDarkBlue]), borderRadius: BorderRadius.circular(3)),
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
