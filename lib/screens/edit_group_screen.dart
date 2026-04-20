import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/expense.dart';
import '../models/group_member.dart';
import '../models/settlement_group.dart';
import '../models/settlement_record.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../utils/settlement_helper.dart';
import '../widgets/app_shell_widgets.dart';
import '../widgets/member_management_widgets.dart'; // New shared widgets
import 'contact_picker_screen.dart';


class EditGroupScreen extends StatefulWidget {
  const EditGroupScreen({
    super.key,
    required this.group,
    required this.expenses,
    required this.settlements,
    required this.profile,
  });

  final SettlementGroup group;
  final List<Expense> expenses;
  final List<SettlementRecord> settlements;
  final UserProfile profile;

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final List<MemberDraft> _members;
  late final Map<String, double> _balances;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _balances = computeMemberBalances(
      members: widget.group.members,
      expenses: widget.expenses,
      settlements: widget.settlements,
    );
    _members = widget.group.members
        .map((m) => MemberDraft.fromMember(m, currentUserProfile: widget.profile))
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final m in _members) {
      m.dispose();
    }
    super.dispose();
  }

  bool _canRemove(String memberId) {
    // A member can be removed only if they are settled up (balance is zero).
    return (_balances[memberId] ?? 0.0).abs() < 0.01;
  }

  void _removeMember(int index) {
    final draft = _members[index];
    if (!_canRemove(draft.id)) {
      final balance = _balances[draft.id] ?? 0.0;
      final msg = balance > 0
          ? '${draft.nameController.text} is owed ₹${formatAmount(balance)}. Settle up first.'
          : '${draft.nameController.text} owes ₹${formatAmount(balance.abs())}. Settle up first.';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    setState(() {
      final removed = _members.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _handleDeleteGroup() async {
    final appState = context.read<AppState>();
    
    // Check if anyone owes anything
    final totalOwes = _balances.values.fold<double>(0, (sum, b) => sum + b.abs());
    if (totalOwes > 0.01) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('All balances must be settled before deleting the group.'))
       );
       return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40),
        title: const Text('Delete Group', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to delete "${widget.group.name}"?', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, fontSize: 15)),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
                ),
              ],
            ),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );

    if (confirmed == true && mounted) {
      // Find my profile to get actor name
      final myProfile = _members.firstWhere((m) => m.isSelf).registeredProfile;
      final actorName = myProfile?.displayName ?? 'User';
      
      await appState.deleteGroup(widget.group.id, actorName);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  void _addManualMember() => _openMemberSheet(null);

  Future<void> _importContacts() async {
    final imported = await Navigator.of(context).push<List<GroupMember>>(
      MaterialPageRoute(builder: (_) => const ContactPickerScreen()),
    );
    if (imported == null || imported.isEmpty || !mounted) return;
    final appState = context.read<AppState>();

    setState(() {
      for (final member in imported) {
        final normalizedImportedPhone = member.phoneNumber != null ? AppState.normalisePhone(member.phoneNumber!) : null;

        final exists = _members.any((d) {
          if (d.id == member.id) return true;
          if (normalizedImportedPhone == null) return false;

          final dPhone = d.phoneController.text.trim();
          if (dPhone.isEmpty) return false;

          return AppState.normalisePhone(dPhone) == normalizedImportedPhone;
        });

        if (!exists) {
          final draft = MemberDraft.fromMember(member, currentUserProfile: widget.profile);
          _members.add(draft);
          if (member.phoneNumber != null && member.phoneNumber!.isNotEmpty) {
            _performLookup(appState, draft);
          }
        }
      }
    });
  }

  Future<void> _performLookup(AppState appState, MemberDraft draft) async {
    final phone = draft.phoneController.text.trim();
    if (phone.length < 5) return; // Standardized
    final profile = await appState.lookupUserByContact(phone);
    if (!mounted) return;
    setState(() {
      draft.registeredProfile = profile;
      if (profile != null) {
        if (draft.nameController.text.trim().isEmpty) {
          draft.nameController.text = profile.displayName;
        }
        if (profile.upiId.isNotEmpty && draft.upiController.text.trim().isEmpty) {
          draft.upiController.text = profile.upiId;
        }
      }
    });
  }

  Future<void> _openMemberSheet(int? editIndex) async {
    final isEdit = editIndex != null;
    final existing = isEdit ? _members[editIndex] : null;

    final result = await showModalBottomSheet<MemberSheetResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => MemberSheet(
        initialName: existing?.nameController.text ?? '',
        initialContact: existing?.phoneController.text ?? '',
        initialUpi: existing?.upiController.text ?? '',
        initialProfile: existing?.registeredProfile,
        existingUid: existing?.existingUid,
        isEdit: isEdit,
        isSelf: existing?.isSelf ?? false,
      ),
    );

    if (result == null || !mounted) return;
    if (isEdit) {
      existing!.nameController.text = result.name;
      existing.phoneController.text = result.phone;
      existing.upiController.text = result.upi;
      existing.registeredProfile = result.profile;
    } else {
      final draft = MemberDraft(
        id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
        nameController: TextEditingController(text: result.name),
        phoneController: TextEditingController(text: result.phone),
        upiController: TextEditingController(text: result.upi),
      );
      draft.registeredProfile = result.profile;
      _members.add(draft);
    }
    setState(() {});
  }

  void _shareInvite() {
    final name = _nameController.text.trim();
    // Use production domain for cross-platform link stability
    const baseUrl = 'https://bharat-dues.web.app';
    final joinUrl = '$baseUrl/#/?join=${widget.group.id}';
    
    final text = 'Hey, join our group "$name" on Bharat Dues to track our expenses together!\n\n'
                'Click here to join: $joinUrl'; 
    Share.share(text, subject: 'Invite to group: $name');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final appState = context.read<AppState>();
    final newName = _nameController.text.trim();
    final newMembers = _members
        .map((d) => d.toMember())
        .where((m) => m.name.trim().isNotEmpty)
        .toList();

    if (newName != widget.group.name) {
      await appState.updateGroupName(groupId: widget.group.id, name: newName);
    }

    String? newCreatorId;
    final bool creatorLeft = !newMembers.any((m) => m.id == widget.group.createdBy);
    
    if (creatorLeft && newMembers.isNotEmpty) {
      // Automatic ownership transfer to the first available member
      newCreatorId = newMembers.first.id;
    }

    await appState.updateGroupMembers(
      groupId: widget.group.id, 
      members: newMembers,
      newCreatorId: newCreatorId,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  void _exportCsv() {
    final buffer = StringBuffer();
    final members = widget.group.members;
    
    // Header
    final header = [
      'Date',
      'Description',
      'Category',
      'Payer',
      'Total Amount',
      ...members.map((m) => '${m.name} (Share)'),
    ];
    buffer.writeln(header.map((v) => '"$v"').join(','));

    for (final e in widget.expenses) {
      final payer = members.firstWhere(
        (m) => m.id == e.payerId, 
        orElse: () => GroupMember(id: '', name: 'Unknown'),
      );
      final date = "${e.createdAt.day}/${e.createdAt.month}/${e.createdAt.year}";
      
      final row = [
        date,
        e.description,
        e.resolvedCategory.label,
        payer.name,
        formatAmount(e.amount),
        ...members.map((m) => formatAmount(e.shares[m.id] ?? 0.0)),
      ];
      buffer.writeln(row.map((v) => '"$v"').join(','));
    }

    Share.share(buffer.toString(), subject: '${widget.group.name} Expenses Report');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Group')),
      body: AppBackdrop(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                   AppSurface(
                    child: Column(
                      children: [
                        const SectionHeading(
                          title: 'Edit Group',
                          subtitle: 'Rename the group, add members, or remove settled participants.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: true, // Democratic renaming
                          decoration: const InputDecoration(
                            labelText: 'Group Name',
                            prefixIcon: Icon(Icons.group_work_outlined),
                            suffixIcon: Icon(Icons.edit_outlined, size: 16),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _addManualMember,
                                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                                label: const Text('Add Member'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _importContacts,
                                icon: const Icon(Icons.contacts_outlined, size: 18),
                                label: const Text('Import Friends'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: _members.asMap().entries.map((entry) {
                      final index = entry.key;
                      final draft = entry.value;
                      final balance = _balances[draft.id] ?? 0.0;
                      final canRemove = _canRemove(draft.id);

                      return Padding(
                        padding: EdgeInsets.only(bottom: index == _members.length - 1 ? 0 : 6.0),
                        child: CompactMemberTile(
                          name: draft.nameController.text,
                          phone: draft.phoneController.text,
                          upiId: draft.upiController.text,
                          isRegistered: draft.registeredProfile != null,
                          isSelf: draft.isSelf,
                          canRemove: canRemove,
                          onTap: () => _openMemberSheet(index),
                          onRemove: () => _removeMember(index),
                          trailing: balance != 0
                              ? Text(
                                  balance > 0 ? '+₹${formatAmount(balance)}' : '−₹${formatAmount(balance.abs())}',
                                  style: TextStyle(
                                    color: balance > 0 ? const Color(0xFF00897B) : Colors.red.shade700,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('Update Group'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _exportCsv,
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('Export Expenses (CSV)'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _shareInvite,
                        icon: const Icon(Icons.ios_share_outlined),
                        label: const Text('Share Group Invite'),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _handleDeleteGroup,
                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        icon: const Icon(Icons.delete_outline, size: 20),
                        label: const Text('Delete Group'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
