import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group_member.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../widgets/app_shell_widgets.dart';
import 'contact_picker_screen.dart';

class GroupFormScreen extends StatefulWidget {
  const GroupFormScreen({super.key});

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  final List<_MemberDraft> _members = [];

  @override
  void dispose() {
    _groupNameController.dispose();
    for (final member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  void _addManualMember() {
    _openMemberSheet(null);
  }

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
    final contact = draft.phoneController.text.trim();
    if (contact.length < 5) {
      if (draft.registeredProfile != null) {
        setState(() => draft.registeredProfile = null);
      }
      return;
    }
    final profile = await appState.lookupUserByContact(contact);
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

  /// Opens a bottom sheet to add or edit a member.
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final members = _members
        .map((d) => d.toMember())
        .where((m) => m.name.trim().isNotEmpty)
        .toList();
    Navigator.of(context).pop(
      GroupFormResult(
        groupName: _groupNameController.text.trim(),
        members: members,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Group')),
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
                          title: 'Create a group',
                          subtitle: 'Name it, add people, then start splitting.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _groupNameController,
                          decoration: const InputDecoration(labelText: 'Group Name'),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return 'Enter a group name';
                            return null;
                          },
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
                  if (_members.isEmpty)
                    const AppSurface(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'No members yet.  Tap "Add" to enter details or "Import" from contacts.',
                          style: TextStyle(color: Colors.white70, height: 1.5),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: _members.asMap().entries.map((entry) {
                        final index = entry.key;
                        final draft = entry.value;
                        return Padding(
                          padding: EdgeInsets.only(bottom: index == _members.length - 1 ? 0 : 6.0),
                          child: _CompactMemberTile(
                            name: draft.nameController.text,
                            phone: draft.phoneController.text,
                            upiId: draft.upiController.text,
                            isRegistered: draft.registeredProfile != null,
                            onTap: () => _openMemberSheet(index),
                            onRemove: () {
                              setState(() {
                                final removed = _members.removeAt(index);
                                removed.dispose();
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Save Group'),
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

// ─── Compact member tile ─────────────────────────────────────────────────

class _CompactMemberTile extends StatelessWidget {
  const _CompactMemberTile({
    required this.name,
    required this.phone,
    required this.upiId,
    required this.isRegistered,
    required this.onTap,
    required this.onRemove,
  });

  final String name;
  final String phone;
  final String upiId;
  final bool isRegistered;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final subtitle = [
      if (phone.isNotEmpty) phone,
      if (upiId.isNotEmpty) upiId,
    ].join(' · ');

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
              // Avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: kAccent.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: kAccent,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name.isNotEmpty ? name : 'New member',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isRegistered) ...[
                          const SizedBox(width: 6),
                          _badge('✓', kAccent),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white38,
                    ),
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
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
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
    final rawPhone = phoneController.text.trim();
    // Accounting ID is the generated 'manual_...' ID. 
    // If a profile is found, we store the UID separately.
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

class GroupFormResult {
  GroupFormResult({
    required this.groupName,
    required this.members,
  });

  final String groupName;
  final List<GroupMember> members;
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
