import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group_member.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../widgets/app_shell_widgets.dart';
import '../widgets/member_management_widgets.dart'; // New shared widgets
import 'contact_picker_screen.dart';

class GroupFormScreen extends StatefulWidget {
  const GroupFormScreen({super.key});

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  final List<MemberDraft> _members = [];

  @override
  void initState() {
    super.initState();
    // Pre-populate "You" so the creator sees themselves in the list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addSelfAsMember();
    });
  }

  void _addSelfAsMember() {
    final appState = context.read<AppState>();
    final currentUser = appState.auth.currentUser;
    if (currentUser == null) return;

    // We need the profile to get the name/upi
    final profileStream = appState.profileStream(currentUser.uid);
    profileStream.first.then((profile) {
      if (profile != null && mounted) {
        setState(() {
          // Check if already added (safety)
          if (!_members.any((m) => m.isSelf)) {
            _members.insert(0, MemberDraft(
              id: profile.uid,
              nameController: TextEditingController(text: profile.displayName),
              phoneController: TextEditingController(text: profile.phoneNumber ?? ''),
              upiController: TextEditingController(text: profile.upiId),
              existingUid: profile.uid,
              photoUrl: profile.photoUrl,
              isSelf: true,
            ));
          }
        });
      }
    });
  }

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
        final normalizedImportedPhone = member.phoneNumber != null ? AppState.normalisePhone(member.phoneNumber!) : null;
        
        final exists = _members.any((d) {
          if (d.id == member.id) return true;
          if (normalizedImportedPhone == null) return false;
          
          final dPhone = d.phoneController.text.trim();
          if (dPhone.isEmpty) return false;
          
          return AppState.normalisePhone(dPhone) == normalizedImportedPhone;
        });

        if (!exists) {
          final draft = MemberDraft.fromMember(member);
          _members.add(draft);
          if (member.phoneNumber != null && member.phoneNumber!.isNotEmpty) {
            _performLookup(appState, draft);
          }
        }
      }
    });
  }

  Future<void> _performLookup(AppState appState, MemberDraft draft) async {
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    
    // Check if at least one member (other than self) is added
    if (_members.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one other member to the group.')),
      );
      return;
    }

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
                          subtitle: 'Name your group, add members, and start splitting expenses.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _groupNameController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Group Name',
                            prefixIcon: Icon(Icons.group_work_outlined),
                          ),
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
                  if (_members.isEmpty)
                    const AppSurface(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'No members yet. Tap "Add" to manually add details or "Import" from your contacts.',
                          style: TextStyle(color: Colors.black45, height: 1.5),
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
                          child: CompactMemberTile(
                            name: draft.nameController.text,
                            phone: draft.phoneController.text,
                            upiId: draft.upiController.text,
                            isRegistered: draft.registeredProfile != null,
                            isSelf: draft.isSelf,
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

class GroupFormResult {
  GroupFormResult({
    required this.groupName,
    required this.members,
  });

  final String groupName;
  final List<GroupMember> members;
}
