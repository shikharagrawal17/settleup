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
import 'contact_picker_screen.dart';


class EditGroupScreen extends StatefulWidget {
  const EditGroupScreen({
    super.key,
    required this.group,
    required this.expenses,
    required this.settlements,
    required this.currentUserId,
  });

  final SettlementGroup group;
  final List<Expense> expenses;
  final List<SettlementRecord> settlements;
  final String currentUserId;

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final List<_MemberDraft> _members;
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
    final currentUserId = widget.currentUserId;
    _members = widget.group.members
        .map((m) => _MemberDraft.fromMember(m, currentUserId))
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
    // Democracy: anyone can remove (Fix 1 updated).
    // Balance check still applies (Fix 2).
    return (_balances[memberId] ?? 0.0) == 0;
  }

  void _removeMember(int index) {
    final draft = _members[index];
    if (!_canRemove(draft.id)) {
      final balance = _balances[draft.id] ?? 0.0;
      final msg = balance > 0
          ? '${draft.nameController.text} is owed ₹$balance. Settle first.'
          : '${draft.nameController.text} owes ₹${balance.abs()}. Settle first.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    setState(() {
      final removed = _members.removeAt(index);
      removed.dispose();
    });
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
        final exists = _members.any((d) => d.id == member.id);
        if (!exists) {
          final draft = _MemberDraft.fromMember(member, widget.currentUserId);
          _members.add(draft);
          if (member.phoneNumber != null && member.phoneNumber!.isNotEmpty) {
            _performLookup(appState, draft);
          }
        }
      }
    });
  }

  Future<void> _performLookup(AppState appState, _MemberDraft draft) async {
    final phone = draft.phoneController.text.trim();
    if (phone.length < 10) return;
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

    final result = await showModalBottomSheet<_MemberSheetResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _MemberSheet(
        initialName: existing?.nameController.text ?? '',
        initialContact: existing?.phoneController.text ?? '',
        initialUpi: existing?.upiController.text ?? '',
        initialProfile: existing?.registeredProfile,
        isEdit: isEdit,
      ),
    );

    if (result == null || !mounted) return;
    if (isEdit) {
      existing!.nameController.text = result.name;
      existing.phoneController.text = result.phone;
      existing.upiController.text = result.upi;
      existing.registeredProfile = result.profile;
    } else {
      final draft = _MemberDraft(
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
        e.amount.toString(),
        ...members.map((m) => (e.shares[m.id] ?? 0).toString()),
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
                          subtitle: 'Rename, add new people, or remove settled members.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          enabled: true, // Democratic renaming
                          decoration: const InputDecoration(
                            labelText: 'Group Name',
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
                                icon: const Icon(Icons.person_add_alt_1, size: 18),
                                label: const Text('Add'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _importContacts,
                                icon: const Icon(Icons.contacts_outlined, size: 18),
                                label: const Text('Import'),
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
                        child: _CompactMemberTile(
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
                        child: const Text('Save Changes'),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Compact member tile (shared with group form) ─────────────────────────

class _CompactMemberTile extends StatelessWidget {
  const _CompactMemberTile({
    required this.name,
    required this.phone,
    required this.upiId,
    required this.isRegistered,
    required this.onTap,
    required this.onRemove,
    this.trailing,
    this.canRemove = true,
    this.isSelf = false,
  });

  final String name;
  final String phone;
  final String upiId;
  final bool isRegistered;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final Widget? trailing;
  final bool canRemove;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final subtitleParts = [
      if (phone.isNotEmpty) phone,
      if (upiId.isNotEmpty) upiId,
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: kPrimaryBlue.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: Text(initial,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: kPrimaryBlue, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name.isNotEmpty ? name : 'Unnamed',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          _badge('You', kDarkBlue),
                        ],
                        if (isRegistered) ...[
                          const SizedBox(width: 6),
                          _badge('✓', kPrimaryBlue),
                        ],
                      ],
                    ),
                    if (subtitleParts.isNotEmpty)
                        Text(
                          subtitleParts.join(' · '),
                          style: const TextStyle(color: Colors.black45, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing!,
              ],
              if (!isSelf)
                GestureDetector(
                  onTap: canRemove ? onRemove : null,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.close, size: 16,
                        color: canRemove ? Colors.black38 : Colors.black12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ─── Member draft ─────────────────────────────────────────────────────────

class _MemberDraft {
  _MemberDraft({
    required this.id,
    required this.nameController,
    required this.phoneController,
    required this.upiController,
    this.isSelf = false,
  });

  final String id;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController upiController;
  final bool isSelf;
  UserProfile? registeredProfile;

  factory _MemberDraft.fromMember(GroupMember member, String currentUserId) {
    return _MemberDraft(
      id: member.id,
      nameController: TextEditingController(text: member.name),
      phoneController: TextEditingController(text: member.phoneNumber ?? ''),
      upiController: TextEditingController(text: member.upiId ?? ''),
      isSelf: member.id == currentUserId || (member.uid != null && member.uid == currentUserId),
    );
  }

  GroupMember toMember() {
    final rawPhone = phoneController.text.trim();
    // Use the stored UID if found, but do NOT change the accounting ID if it's already set.
    return GroupMember(
      id: id,
      name: nameController.text.trim(),
      phoneNumber: rawPhone.isEmpty ? null : AppState.normalisePhone(rawPhone),
      upiId: upiController.text.trim().isEmpty ? null : upiController.text.trim(),
      uid: registeredProfile?.uid,
      isSelf: isSelf,
    );
  }

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    upiController.dispose();
  }
}

// ─── Member sheet result ───────────────────────────────────────────────────

class _MemberSheetResult {
  const _MemberSheetResult({
    required this.name,
    required this.phone,
    required this.upi,
    this.profile,
  });
  final String name;
  final String phone;
  final String upi;
  final UserProfile? profile;
}

// ─── Member bottom-sheet widget ────────────────────────────────────────────

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({
    required this.initialName,
    required this.initialContact,
    required this.initialUpi,
    required this.isEdit,
    this.initialProfile,
  });

  final String initialName;
  final String initialContact;
  final String initialUpi;
  final bool isEdit;
  final UserProfile? initialProfile;

  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  late final TextEditingController _name;
  late final TextEditingController _contact;
  late final TextEditingController _upi;
  final _formKey = GlobalKey<FormState>();
  UserProfile? _profile;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _contact = TextEditingController(text: widget.initialContact);
    _upi = TextEditingController(text: widget.initialUpi);
    _profile = widget.initialProfile;
    _contact.addListener(_onContactChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _contact.removeListener(_onContactChanged);
    _name.dispose();
    _contact.dispose();
    _upi.dispose();
    super.dispose();
  }

  void _onContactChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final contactValue = _contact.text.trim();
      if (contactValue.length < 5) return;
      final appState = context.read<AppState>();
      final profile = await appState.lookupUserByContact(contactValue);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        if (profile != null) {
          if (_name.text.trim().isEmpty) _name.text = profile.displayName;
          // Background auto-fill from discovery, but no longer editable by creator
          if (profile.upiId.isNotEmpty) {
            _upi.text = profile.upiId;
          }
        }
      });
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _MemberSheetResult(
        name: _name.text.trim(),
        phone: _contact.text.trim(),
        upi: _upi.text.trim(),
        profile: _profile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: AppSurface(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: widget.isEdit ? 'Edit Member' : 'Add Member',
                subtitle: 'Enter details — phone numbers & emails auto-fetch registered users.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name', isDense: true),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contact,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Phone Number or Email',
                  prefixIcon: Icon(Icons.contact_mail_outlined, size: 20),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(widget.isEdit ? 'Save' : 'Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
