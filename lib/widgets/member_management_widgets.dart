import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group_member.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../widgets/app_shell_widgets.dart';

// ─── Member Draft Model ──────────────────────────────────────────────────

class MemberDraft {
  MemberDraft({
    required this.id,
    required this.nameController,
    required this.phoneController,
    required this.upiController,
    this.existingUid,
    this.photoUrl,
    this.isSelf = false,
  });

  final String id;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController upiController;
  final String? existingUid;
  final String? photoUrl;
  final bool isSelf;
  UserProfile? registeredProfile;

  factory MemberDraft.fromMember(GroupMember member, {UserProfile? currentUserProfile}) {
    bool isSelf = member.isSelf;
    if (currentUserProfile != null && !isSelf) {
      final currentUid = currentUserProfile.uid;
      final currentPhone = (currentUserProfile.phoneNumber ?? '').isNotEmpty 
          ? AppState.normalisePhone(currentUserProfile.phoneNumber!) : null;
      final mPhone = (member.phoneNumber ?? '').isNotEmpty 
          ? AppState.normalisePhone(member.phoneNumber!) : null;
      
      isSelf = member.id == currentUid || 
               (member.uid != null && member.uid == currentUid) || 
               (currentPhone != null && mPhone != null && mPhone == currentPhone);
    }

    return MemberDraft(
      id: member.id,
      nameController: TextEditingController(text: member.name),
      phoneController: TextEditingController(text: member.phoneNumber ?? ''),
      upiController: TextEditingController(text: member.upiId ?? ''),
      existingUid: member.uid,
      photoUrl: member.photoUrl,
      isSelf: isSelf,
    );
  }

  GroupMember toMember() {
    final rawPhone = phoneController.text.trim();
    return GroupMember(
      id: id,
      name: nameController.text.trim(),
      phoneNumber: rawPhone.isEmpty ? null : AppState.normalisePhone(rawPhone),
      upiId: upiController.text.trim().isEmpty ? null : upiController.text.trim(),
      uid: registeredProfile?.uid ?? existingUid,
      photoUrl: registeredProfile?.photoUrl ?? photoUrl,
      isSelf: isSelf,
    );
  }

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    upiController.dispose();
  }
}

// ─── Member Sheet Result ──────────────────────────────────────────────────

class MemberSheetResult {
  const MemberSheetResult({
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

// ─── Shared Compact Member Tile ──────────────────────────────────────────

class CompactMemberTile extends StatelessWidget {
  const CompactMemberTile({
    super.key,
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
                            name.isNotEmpty ? name : (isSelf ? 'You' : 'Unnamed'),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          _badge('You', kDarkBlue),
                        ] else if (isRegistered) ...[
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
              if (canRemove && !isSelf)
                GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.close, size: 16, color: Colors.black38),
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

// ─── Shared Member Bottom Sheet ──────────────────────────────────────────

class MemberSheet extends StatefulWidget {
  const MemberSheet({
    super.key,
    required this.initialName,
    required this.initialContact,
    required this.initialUpi,
    required this.isEdit,
    this.initialProfile,
    this.existingUid,
    this.isSelf = false,
  });

  final String initialName;
  final String initialContact;
  final String initialUpi;
  final bool isEdit;
  final UserProfile? initialProfile;
  final String? existingUid;
  final bool isSelf;

  @override
  State<MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<MemberSheet> {
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
      // Standardized lookup threshold
      if (contactValue.length < 5) {
        if (_profile != null) {
          setState(() {
            _profile = null;
          });
        }
        return;
      }
      
      final appState = context.read<AppState>();
      final profile = await appState.lookupUserByContact(contactValue);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        if (profile != null) {
          if (_name.text.trim().isEmpty) _name.text = profile.displayName;
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
      MemberSheetResult(
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
    
    // A member is "registered" if they have an existing UID or a profile was discovered.
    final isRegistered = widget.existingUid != null || _profile != null;
    
    // UPI ID can only be edited if the member is NOT registered, OR if it's the current user themselves
    final canEditUpi = !isRegistered || widget.isSelf;

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
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name', 
                  isDense: true,
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contact,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Phone Number or Email',
                  prefixIcon: Icon(Icons.contact_mail_outlined, size: 20),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _upi,
                enabled: canEditUpi,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: 'UPI ID (Optional)',
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                  isDense: true,
                  hintText: 'username@bank',
                  helperText: !canEditUpi ? 'Registered user\'s UPI ID cannot be edited.' : null,
                  helperStyle: const TextStyle(fontSize: 10, color: Colors.blueAccent),
                ),
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    final appState = context.read<AppState>();
                    return appState.validateUpiId(v);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(widget.isEdit ? 'Save Changes' : 'Add Member'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
