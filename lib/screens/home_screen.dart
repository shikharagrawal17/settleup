import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settlement_group.dart';
import '../models/group_member.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../widgets/app_shell_widgets.dart';
import '../utils/settlement_helper.dart';
import 'group_form_screen.dart';
import 'group_settlement_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.profile,
  });

  final User user;
  final UserProfile profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      appState.initMessaging();
      appState.loadLocalContacts();
    });
  }

  Future<void> _openCreateGroup(
    BuildContext context,
    AppState appState,
    UserProfile profile,
  ) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const GroupFormScreen(),
      ),
    );

    if (result is! GroupFormResult) {
      return;
    }

    await appState.createGroup(
      profile: profile,
      name: result.groupName,
      members: result.members,
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    AppState appState,
    UserProfile profile,
  ) async {
    final upiController = TextEditingController(text: profile.upiId);
    final phoneController = TextEditingController(text: profile.phoneNumber ?? '');
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
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
                    const SectionHeading(
                      title: 'Your Profile',
                      subtitle: 'Keep your UPI handle up to date so group members can settle directly.',
                    ),
                    const SizedBox(height: 18),
                    _ReadOnlyField(
                      icon: Icons.email_outlined,
                      label: 'Google Email',
                      value: profile.email,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: upiController,
                      decoration: const InputDecoration(
                        labelText: 'UPI ID (e.g. name@upi)',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          return appState.validateUpiId(value);
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          await appState.saveProfile(
                            upiId: upiController.text.trim(),
                            phoneNumber: phoneController.text.trim(),
                          );
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Save Profile'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Version: 1.0.5+sync-hardened',
                        style: TextStyle(color: Colors.white12, fontSize: 10),
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

  Future<void> _handleDeleteGroup(AppState appState, String groupId, String groupName) async {
    await appState.deleteGroup(groupId);
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "$groupName"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => appState.restoreGroup(groupId),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final profile = widget.profile;

    return StreamBuilder<List<SettlementGroup>>(
      stream: appState.groupsStream(uid: profile.uid, phoneNumber: profile.phoneNumber),
      builder: (context, groupSnapshot) {
        final groups = groupSnapshot.data ?? const <SettlementGroup>[];
        final regularGroups = groups.where((g) => !g.isNonGroup).toList();

        return Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    Image.asset('assets/images/logo.png', height: 28),
                    const SizedBox(width: 10),
                    const Text('Bharat Dues'),
                  ],
                ),
                actions: [
                  IconButton(
                    onPressed: () => _editProfile(context, appState, profile),
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                  IconButton(
                    onPressed: appState.signOut,
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
              floatingActionButton: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'addGroup',
                    onPressed: () => _openCreateGroup(context, appState, profile),
                    icon: const Icon(Icons.groups),
                    label: const Text('New Group'),
                  ),
                ],
              ),
              body: SafeArea(
                child: AppBackdrop(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DashboardSummary(
                          profile: profile,
                          groups: regularGroups,
                          onEditProfile: () => _editProfile(context, appState, profile),
                        ),
                        const SizedBox(height: 24),
                        const SectionHeading(
                          title: 'Your Groups',
                          subtitle: 'Circles for roommates, trips, and more.',
                        ),
                        const SizedBox(height: 14),
                        if (regularGroups.isEmpty)
                          _EmptyGroups(onCreate: () => _openCreateGroup(context, appState, profile))
                        else
                          _GroupList(
                            groups: regularGroups,
                            profile: profile,
                            currentUserId: widget.user.uid,
                            onDelete: (id) => _handleDeleteGroup(appState, id, regularGroups.firstWhere((g) => g.id == id).name),
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
}

class _DashboardSummary extends StatelessWidget {
  const _DashboardSummary({
    required this.profile,
    required this.groups,
    required this.onEditProfile,
  });

  final UserProfile profile;
  final List<SettlementGroup> groups;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    return FutureBuilder<Map<String, double>>(
      future: _calculateTotalBalances(appState, groups, profile.uid),
      builder: (context, snapshot) {
        final data = snapshot.data ?? {'net': 0, 'owe': 0, 'owed': 0};
        final net = data['net'] ?? 0;
        final owe = data['owe'] ?? 0;
        final owed = data['owed'] ?? 0;

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, ${profile.displayName.split(' ').first}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        groups.isEmpty ? 'Start by adding a friend' : 'Your financial summary',
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onEditProfile,
                  icon: const Icon(Icons.settings_outlined, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D2A4A), Color(0xFF1F1D36)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL NET BALANCE', 
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Text(
                    '₹${formatAmount(net.abs())}',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: net == 0 ? Colors.white : (net > 0 ? const Color(0xFF4ADE80) : Colors.redAccent),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _MiniBalance(label: 'YOU OWE', amount: '₹${formatAmount(owe)}', color: Colors.redAccent)),
                      const SizedBox(width: 12),
                      Expanded(child: _MiniBalance(label: 'YOU ARE OWED', amount: '₹${formatAmount(owed)}', color: const Color(0xFF4ADE80))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: 'PAYOUT UPI ID',
                    value: profile.hasUpiId ? profile.upiId : 'Not Set',
                    highlight: profile.hasUpiId,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricPill(
                    label: 'ACTIVE GROUPS',
                    value: '${groups.length}',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, double>> _calculateTotalBalances(AppState appState, List<SettlementGroup> groups, String uid) async {
    double totalOwe = 0;
    double totalOwed = 0;

    for (final group in groups) {
      final expenses = await appState.expensesStream(group.id).first;
      final settlements = await appState.settlementsStream(group.id).first;
      final balances = computeMemberBalances(
        members: group.members,
        expenses: expenses,
        settlements: settlements,
      );
      
      // Check for balance using both UID and Phone Number
      final myUidBalance = balances[uid] ?? 0.0;
      final myPhoneBalance = (profile.phoneNumber != null) ? (balances[profile.phoneNumber!] ?? 0.0) : 0.0;
      
      final myBalance = (myUidBalance.abs() > myPhoneBalance.abs()) ? myUidBalance : myPhoneBalance;

      if (myBalance > 0.005) {
        totalOwed += myBalance;
      } else if (myBalance < -0.005) {
        totalOwe += myBalance.abs();
      }
    }

    return {
      'net': totalOwed - totalOwe,
      'owe': totalOwe,
      'owed': totalOwed,
    };
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.profile,
    required this.currentUserId,
    required this.onDelete,
  });

  final List<SettlementGroup> groups;
  final UserProfile profile;
  final String currentUserId;
  final Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: groups.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _GroupCard(
          group: group,
          currentUserId: currentUserId,
          onOpen: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupSettlementScreen(group: group, profile: profile),
              ),
            );
          },
          onDelete: () => onDelete(group.id),
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.currentUserId,
    required this.onOpen,
    required this.onDelete,
  });

  final SettlementGroup group;
  final String currentUserId;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    String displayName = group.name;

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(24),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: group.isNonGroup 
                    ? [const Color(0xFF63B3ED), const Color(0xFF3182CE)] 
                    : [kAccent, kSecondary],
                ),
              ),
              child: Icon(
                group.isNonGroup ? Icons.person_outline : Icons.group_outlined, 
                color: Colors.black, 
                size: 26
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 4),
                  Text(
                    '${group.members.length} members',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () async {
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
                            const Text('Delete Group', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                            const SizedBox(height: 12),
                            Text('Are you sure you want to delete "$displayName"?', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 12),
                            const Text('You can undo this immediately from the main screen.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white24, fontSize: 12)),
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
                if (confirmed == true) onDelete();
              },
              icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white12, size: 14),
          ],
        ),
      ),
    );
  }
}

class _MiniBalance extends StatelessWidget {
  const _MiniBalance({required this.label, required this.amount, required this.color});
  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(amount, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white38),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }
}

// Unused widgets removed

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCreate,
      borderRadius: BorderRadius.circular(24),
      child: AppSurface(
        child: const Column(
          children: [
            Icon(Icons.groups_3_outlined, size: 32, color: kAccent),
            SizedBox(height: 12),
            Text('No groups yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 4),
            Text('Groups are perfect for trips and housemates.', style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
