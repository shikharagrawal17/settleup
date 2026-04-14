import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  });

  final SettlementGroup group;
  final List<Expense> expenses;
  final List<SettlementRecord> settlements;

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final List<_MemberDraft> _members;
  late final Map<String, int> _balances;

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
        .map((m) => _MemberDraft.fromMember(m))
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
    final member = widget.group.members.where((m) => m.id == memberId).firstOrNull;
    if (member != null && member.isSelf) return false;
    return (_balances[memberId] ?? 0) == 0;
  }

  void _removeMember(int index) {
    final draft = _members[index];
    if (!_canRemove(draft.id)) {
      final balance = _balances[draft.id] ?? 0;
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
          final draft = _MemberDraft.fromMember(member);
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
    await appState.updateGroupMembers(groupId: widget.group.id, members: newMembers);
    if (mounted) Navigator.of(context).pop(true);
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
                          decoration: const InputDecoration(labelText: 'Group Name'),
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
                      final balance = _balances[draft.id] ?? 0;
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
                                  balance > 0 ? '+₹$balance' : '−₹${balance.abs()}',
                                  style: TextStyle(
                                    color: balance > 0 ? const Color(0xFF4ADE80) : Colors.redAccent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
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
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: kAccent.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: Text(initial,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: kAccent, fontSize: 14)),
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
                          _badge('You', kSecondary),
                        ],
                        if (isRegistered) ...[
                          const SizedBox(width: 6),
                          _badge('✓', kAccent),
                        ],
                      ],
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
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
                        color: canRemove ? Colors.white38 : Colors.white12),
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

  factory _MemberDraft.fromMember(GroupMember member) {
    return _MemberDraft(
      id: member.id,
      nameController: TextEditingController(text: member.name),
      phoneController: TextEditingController(text: member.phoneNumber ?? ''),
      upiController: TextEditingController(text: member.upiId ?? ''),
      isSelf: member.isSelf,
    );
  }

  GroupMember toMember() {
    return GroupMember(
      id: id,
      name: nameController.text.trim(),
      phoneNumber: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
      upiId: upiController.text.trim().isEmpty ? null : upiController.text.trim(),
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
          if (profile.upiId.isNotEmpty && _upi.text.trim().isEmpty) {
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
              const SizedBox(height: 10),
              TextFormField(
                controller: _upi,
                decoration: const InputDecoration(
                  labelText: 'UPI ID (optional)',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined, size: 20),
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
