import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/settlement_group.dart';
import '../models/group_member.dart';
import '../models/user_profile.dart';
import '../models/expense.dart';
import '../models/settlement_record.dart';
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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      appState.initMessaging();
      appState.loadLocalContacts();

      if (widget.profile.upiId.isEmpty || (widget.profile.phoneNumber ?? '').isEmpty) {
        _editProfile(context, appState, widget.profile);
      }

      // Handle Group Join from pending state
      if (appState.pendingJoinGroupId != null) {
        final id = appState.pendingJoinGroupId!;
        appState.pendingJoinGroupId = null; // Clear it immediately
        _handleJoinGroup(appState, id);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleJoinGroup(AppState appState, String groupId) async {
    try {
      await appState.joinGroup(groupId, widget.profile);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined group successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join group: $e')),
        );
      }
    }
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
                      subtitle: 'Keep your UPI handle updated so group members can settle dues directly.',
                    ),
                    const SizedBox(height: 18),
                    _ReadOnlyField(
                      icon: Icons.person_outline,
                      label: 'Account Name',
                      value: profile.displayName,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        hintText: '+91...',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Enter phone number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: upiController,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'UPI ID (Handle)',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        hintText: 'username@bank',
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          appState.signOut();
                        },
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Sign Out'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Colors.black12),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final url = Uri.parse('https://www.linkedin.com/in/shikhar-agarwal-17jan2002/');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: kPrimaryBlue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.code_rounded, color: kPrimaryBlue, size: 20),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Developed by',
                                    style: TextStyle(color: Colors.black38, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Shikhar Agarwal',
                                    style: TextStyle(color: kDarkBlue, fontWeight: FontWeight.w700, fontSize: 13, decoration: TextDecoration.underline),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.open_in_new_rounded, color: Colors.black26, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'Version: 1.0.6',
                        style: TextStyle(color: Colors.black12, fontSize: 10),
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
    // Check if the group is settled before allowing deletion
    final expenses = await appState.expensesStream(groupId).first;
    final settlements = await appState.settlementsStream(groupId).first;
    
    // We need the group to get the members list
    final groups = await appState.groupsStream(uid: widget.profile.uid, phoneNumber: widget.profile.phoneNumber).first;
    final group = groups.firstWhere((g) => g.id == groupId);

    final balances = computeMemberBalances(
      members: group.members,
      expenses: expenses,
      settlements: settlements,
    );

    // Check if any member has a non-zero balance (using 0.01 epsilon)
    final bool isSettled = balances.values.every((b) => b.abs() < 0.01);

    if (!isSettled) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: AppSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline_rounded, color: kPrimaryBlue, size: 40),
                  const SizedBox(height: 16),
                  const Text('Cannot Delete Group', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: kDarkBlue)),
                  const SizedBox(height: 12),
                  const Text(
                    'This group has unsettled balances. All members must be settled up before the group can be deleted.', 
                    textAlign: TextAlign.center, 
                    style: TextStyle(color: Colors.black87)
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx), 
                      child: const Text('Got it'),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    await appState.deleteGroup(groupId, widget.profile.displayName);
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "$groupName"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => appState.restoreGroup(groupId, widget.profile.displayName),
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
                    icon: profile.photoUrl != null && profile.photoUrl!.isNotEmpty
                        ? CircleAvatar(
                            radius: 14,
                            backgroundImage: NetworkImage(profile.photoUrl!),
                          )
                        : const Icon(Icons.account_circle_outlined),
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
                  child: FutureBuilder<_HomeFinancials>(
                    future: _calculateFinancials(appState, groups, profile), 
                    builder: (context, finSnapshot) {
                      final financials = finSnapshot.data ?? _HomeFinancials.empty();

                      return Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _DashboardSummary(
                                    profile: profile,
                                    financials: financials,
                                    groupsCount: regularGroups.length,
                                    onEditProfile: () => _editProfile(context, appState, profile),
                                  ),
                                  const SizedBox(height: 32),
                                  
                                  // Tab Header
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: TabBar(
                                      controller: _tabController,
                                      dividerColor: Colors.transparent,
                                      indicator: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.05),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      indicatorSize: TabBarIndicatorSize.tab,
                                      labelColor: kPrimaryBlue,
                                      unselectedLabelColor: Colors.black45,
                                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      tabs: const [
                                        Tab(text: 'GROUPS'),
                                        Tab(text: 'FRIENDS'),
                                        Tab(text: 'ACTIVITY'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Tab Content
                                  ValueListenableBuilder<int>(
                                    valueListenable: ValueNotifier(_tabController.index),
                                    builder: (context, _, __) {
                                      return AnimatedBuilder(
                                        animation: _tabController,
                                        builder: (context, _) {
                                          if (_tabController.index == 0) {
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const SectionHeading(
                                                  title: 'Your Groups',
                                                  subtitle: 'Expense tracking for roommates, trips, and more.',
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
                                            );
                                          } else if (_tabController.index == 1) {
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const SectionHeading(
                                                  title: 'All Friends',
                                                  subtitle: 'Total net balances across all shared activities.',
                                                ),
                                                const SizedBox(height: 14),
                                                if (financials.friendBalances.isEmpty)
                                                  const Center(
                                                    child: Padding(
                                                      padding: EdgeInsets.symmetric(vertical: 60),
                                                      child: Column(
                                                        children: [
                                                          Icon(Icons.check_circle_outline_rounded, color: Colors.black12, size: 48),
                                                          SizedBox(height: 16),
                                                          Text('You\'re all settled up!', style: TextStyle(color: Colors.black38, fontWeight: FontWeight.w500)),
                                                        ],
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  _FriendsList(financials: financials, currentProfile: profile),
                                              ],
                                            );
                                          } else {
                                            return _HomeActivityTab(
                                              user: widget.user,
                                              profile: profile,
                                              appState: appState,
                                            );
                                          }
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
      },
    );
  }

  Future<_HomeFinancials> _calculateFinancials(AppState appState, List<SettlementGroup> groups, UserProfile profile) async {
    double totalOwe = 0;
    double totalOwed = 0;
    final Map<String, _FriendBalance> friendBalances = {};
    final List<_PendingSettlementBatch> pendingSettlements = [];
    
    final uid = profile.uid;
    final userPhone = (profile.phoneNumber != null && profile.phoneNumber!.isNotEmpty) 
        ? AppState.normalisePhone(profile.phoneNumber!) 
        : null;

    for (final group in groups) {
      if (group.isDeleted) continue;

      final expenses = await appState.expensesStream(group.id).first;
      final settlementsSnapshot = await appState.settlementsStream(group.id).first;
      
      // Look for pending settlements related to me
      for (final s in settlementsSnapshot) {
        if (s.status == SettlementStatus.pending) {
          final sToPhone = s.toMemberId.startsWith('manual_') && group.members.any((m) => m.id == s.toMemberId) 
              ? AppState.normalisePhone(group.members.firstWhere((m) => m.id == s.toMemberId).phoneNumber ?? '') 
              : null;
          final sFromPhone = s.fromMemberId.startsWith('manual_') && group.members.any((m) => m.id == s.fromMemberId) 
              ? AppState.normalisePhone(group.members.firstWhere((m) => m.id == s.fromMemberId).phoneNumber ?? '') 
              : null;

          final isReceiver = s.toMemberId == uid || 
                            (userPhone != null && sToPhone != null && sToPhone == userPhone) ||
                            (s.toMemberId.startsWith('manual_') && s.toName == profile.displayName);
          
          final isPayer = s.fromMemberId == uid || 
                         (userPhone != null && sFromPhone != null && sFromPhone == userPhone) ||
                         (s.fromMemberId.startsWith('manual_') && s.fromName == profile.displayName);

          if (isReceiver || isPayer) {
            pendingSettlements.add(_PendingSettlementBatch(
              groupId: group.id,
              groupName: group.name,
              record: s,
              isWaitingForMe: isReceiver,
            ));
          }
        }
      }

      final balances = computeMemberBalances(
        members: group.members,
        expenses: expenses,
        settlements: settlementsSnapshot,
      );
      
      double myNetRelGroup = 0;
      final Set<String> myIdsInGroup = {};
      String? myPrimaryIdInGroup;
      
      for (final m in group.members) {
        final mPhone = (m.phoneNumber != null && m.phoneNumber!.isNotEmpty) 
            ? AppState.normalisePhone(m.phoneNumber!) 
            : null;

        final isMe = m.id == uid || 
                     (m.uid != null && m.uid == uid) || 
                     (userPhone != null && mPhone != null && mPhone == userPhone) ||
                     (profile.email.isNotEmpty && m.phoneNumber != null && m.phoneNumber!.toLowerCase().trim() == profile.email.toLowerCase().trim());
        
        if (isMe) {
          myNetRelGroup += balances[m.id] ?? 0.0;
          myIdsInGroup.add(m.id);
          myPrimaryIdInGroup ??= m.id;
        }
      }

      if (myNetRelGroup > 0.005) {
        totalOwed += myNetRelGroup;
      } else if (myNetRelGroup < -0.005) {
        totalOwe += myNetRelGroup.abs();
      }

      for (final m in group.members) {
        if (myIdsInGroup.contains(m.id)) continue;
        
        final balance = balances[m.id] ?? 0.0;
        if (balance.abs() < 0.005) continue;

        final String friendKey = m.uid ?? 
                                 (m.phoneNumber != null ? AppState.normalisePhone(m.phoneNumber!) : null) ?? 
                                 'name_${m.name}';
        
        if (!friendBalances.containsKey(friendKey)) {
          friendBalances[friendKey] = _FriendBalance(
            name: m.name,
            netBalance: 0,
            upiId: m.upiId,
            phoneNumber: m.phoneNumber,
          );
        }
        
        friendBalances[friendKey]!.netBalance += balance;
        friendBalances[friendKey]!.contributions.add(_GroupContribution(
          groupId: group.id,
          groupName: group.name,
          myMemberId: myPrimaryIdInGroup ?? uid,
          friendMemberId: m.id,
          balance: balance,
        ));
      }
    }

    friendBalances.removeWhere((k, v) => v.netBalance.abs() < 0.01);

    return _HomeFinancials(
      net: totalOwed - totalOwe,
      owe: totalOwe,
      owed: totalOwed,
      friendBalances: friendBalances.values.toList()..sort((a, b) => b.netBalance.abs().compareTo(a.netBalance.abs())),
      pendingSettlements: pendingSettlements,
    );
  }
}

class _HomeFinancials {
  final double net;
  final double owe;
  final double owed;
  final List<_FriendBalance> friendBalances;
  final List<_PendingSettlementBatch> pendingSettlements;

  _HomeFinancials({required this.net, required this.owe, required this.owed, required this.friendBalances, this.pendingSettlements = const []});

  factory _HomeFinancials.empty() => _HomeFinancials(net: 0, owe: 0, owed: 0, friendBalances: []);
}

class _PendingSettlementBatch {
  final String groupId;
  final String groupName;
  final SettlementRecord record;
  final bool isWaitingForMe;

  _PendingSettlementBatch({required this.groupId, required this.groupName, required this.record, required this.isWaitingForMe});
}

class _FriendBalance {
  final String name;
  double netBalance;
  final String? upiId;
  final String? phoneNumber;
  final List<_GroupContribution> contributions = [];

  _FriendBalance({required this.name, required this.netBalance, this.upiId, this.phoneNumber});
}

class _GroupContribution {
  final String groupId;
  final String groupName;
  final String myMemberId;
  final String friendMemberId;
  final double balance;

  _GroupContribution({
    required this.groupId,
    required this.groupName,
    required this.myMemberId,
    required this.friendMemberId,
    required this.balance,
  });
}

class _DashboardSummary extends StatelessWidget {
  const _DashboardSummary({
    required this.profile,
    required this.financials,
    required this.groupsCount,
    required this.onEditProfile,
  });

  final UserProfile profile;
  final _HomeFinancials financials;
  final int groupsCount;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final net = financials.net;
    final owe = financials.owe;
    final owed = financials.owed;

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
                    groupsCount == 0 ? 'Start by adding a friend' : 'Your financial summary',
                    style: const TextStyle(color: Colors.black45, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: kPrimaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPrimaryBlue.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TOTAL NET BALANCE', 
                style: TextStyle(color: Colors.black38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(
                '₹${formatAmount(net.abs())}',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: net.abs() < 0.01 ? kDarkBlue : (net > 0 ? const Color(0xFF4ADE80) : Colors.redAccent),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _MiniBalance(label: 'YOU OWE', amount: '₹${formatAmount(owe)}', color: Colors.red.shade700)),
                  const SizedBox(width: 12),
                  Expanded(child: _MiniBalance(label: 'YOU ARE OWED', amount: '₹${formatAmount(owed)}', color: const Color(0xFF4ADE80))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FriendsList extends StatelessWidget {
  const _FriendsList({required this.financials, required this.currentProfile});
  final _HomeFinancials financials;
  final UserProfile currentProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (financials.pendingSettlements.isNotEmpty) ...[
          const SectionHeading(
            title: 'Pending Verify',
            subtitle: 'Verify received payments or track your pending requests.',
          ),
          const SizedBox(height: 12),
          ...financials.pendingSettlements.map((s) => _PendingSettlementCard(pending: s)),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
        ],
        ...financials.friendBalances.map((friend) {
        final net = friend.netBalance;
        final color = net > 0 ? Colors.redAccent : const Color(0xFF4ADE80);
        final statusText = net > 0 ? 'You owe' : 'Is owed';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => _openSettleAllSheet(context, friend, currentProfile),
            child: AppSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: kPrimaryBlue.withValues(alpha: 0.1),
                    child: Text(friend.name[0], style: const TextStyle(color: kPrimaryBlue, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(friend.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(statusText, style: const TextStyle(color: Colors.black38, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${formatAmount(net.abs())}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (net < -0.01 && friend.phoneNumber != null)
                            IconButton(
                              onPressed: () async {
                                final text = 'Hey ${friend.name}, just a friendly reminder about the ₹${formatAmount(net.abs())} balance in our Bharat Dues groups. Please settle when you can! 😉';
                                final url = Uri.parse('whatsapp://send?phone=${friend.phoneNumber}&text=${Uri.encodeComponent(text)}');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF25D366), size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Remind on WhatsApp',
                            ),
                          if (net > 0.01 && friend.upiId != null)
                            IconButton(
                              onPressed: () async {
                                final url = Uri.parse('upi://pay?pa=${friend.upiId}&pn=${Uri.encodeComponent(friend.name)}&am=${formatAmount(net.abs())}&cu=INR');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(Icons.account_balance_wallet_outlined, color: kPrimaryBlue, size: 18),
                              padding: const EdgeInsets.only(left: 10),
                              constraints: const BoxConstraints(),
                              tooltip: 'Pay via UPI',
                            ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: kPrimaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Settle all', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kDarkBlue)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
      ],
    );
  }

  void _openSettleAllSheet(BuildContext context, _FriendBalance friend, UserProfile currentProfile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SettleAllSheet(friend: friend, currentProfile: currentProfile),
    );
  }
}

class _PendingSettlementCard extends StatelessWidget {
  const _PendingSettlementCard({required this.pending});
  final _PendingSettlementBatch pending;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurface(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              pending.isWaitingForMe ? Icons.timer_outlined : Icons.outbox_rounded, 
              color: pending.isWaitingForMe ? Colors.amber : Colors.black26, 
              size: 20
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pending.isWaitingForMe 
                      ? '${pending.record.fromName} paid you' 
                      : 'You paid ${pending.record.toName}', 
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kDarkBlue)
                  ),
                  Text('In ${pending.groupName}', style: const TextStyle(color: Colors.black38, fontSize: 11)),
                ],
              ),
            ),
            Text('₹${formatAmount(pending.record.amount)}', 
              style: TextStyle(
                fontWeight: FontWeight.w800, 
                fontSize: 14, 
                color: pending.isWaitingForMe ? const Color(0xFF00897B) : Colors.black45
              )
            ),
            if (pending.isWaitingForMe) ...[
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => appState.disputeSettlement(groupId: pending.groupId, settlementId: pending.record.id),
                icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Incorrect Payment',
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => appState.confirmSettlement(groupId: pending.groupId, record: pending.record),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: const Color(0xFF4ADE80).withValues(alpha: 0.1),
                  foregroundColor: const Color(0xFF4ADE80),
                ),
                child: const Text('Confirm', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ] else 
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    const Text('Pending', style: TextStyle(color: Colors.black26, fontSize: 10, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => appState.deleteSettlement(groupId: pending.groupId, record: pending.record),
                      icon: const Icon(Icons.delete_sweep_outlined, color: Colors.black26, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Cancel Payment Record',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettleAllSheet extends StatefulWidget {
  const _SettleAllSheet({required this.friend, required this.currentProfile});
  final _FriendBalance friend;
  final UserProfile currentProfile;

  @override
  State<_SettleAllSheet> createState() => _SettleAllSheetState();
}

class _SettleAllSheetState extends State<_SettleAllSheet> {
  bool _isProcessing = false;
  bool _paymentInitiated = false;

  @override
  Widget build(BuildContext context) {
    final net = widget.friend.netBalance;
    final isIowe = net > 0;
    final upiIdToShow = isIowe ? widget.friend.upiId : widget.currentProfile.upiId;
    final nameToShow = isIowe ? widget.friend.name : widget.currentProfile.displayName;
    final hasUpi = upiIdToShow != null && upiIdToShow.isNotEmpty;
    
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 32),
            // Rupee Seal / Identity
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: (isIowe ? Colors.redAccent : const Color(0xFF00897B)).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: (isIowe ? Colors.redAccent : const Color(0xFF00897B)).withValues(alpha: 0.2), width: 2),
                ),
                  child: Center(
                    child: Text(
                      '₹', 
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: isIowe ? Colors.redAccent : const Color(0xFF00897B))
                    ),
                  ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                isIowe ? 'Payment' : 'Record Receipt', 
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22, letterSpacing: -0.5)
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                isIowe ? 'Settling balance with ${widget.friend.name}' : 'You received payment from ${widget.friend.name}',
                style: const TextStyle(color: Colors.black45, fontSize: 13),
              ),
            ),
            const SizedBox(height: 32),
            
            // Move QR to top
            if (hasUpi && !_paymentInitiated) ...[
              _SettleQrBox(
                upiId: upiIdToShow!,
                name: nameToShow,
                amount: net.abs(),
              ),
              if (isIowe) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _handlePay(upiIdToShow!, nameToShow, net.abs()),
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                    label: const Text('Pay via UPI App', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],

            // Transaction Details Card
            AppSurface(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Net Balance', style: TextStyle(color: Colors.black38, fontSize: 13)),
                      Text(
                        '₹${formatAmount(net.abs())}', 
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: isIowe ? Colors.redAccent : const Color(0xFF00897B))
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: Colors.black12),
                  ),
                  Row(
                    children: [
                      Text(isIowe ? 'Payable to: ' : 'From: ', style: const TextStyle(color: Colors.black38, fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.friend.name,
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
            const Text('BREAKDOWN ACROSS GROUPS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1.2, color: Colors.black38)),
            const SizedBox(height: 16),
            Column(
              children: widget.friend.contributions.map((contra) {
                final iOweThis = contra.balance > 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 4, height: 32,
                        decoration: BoxDecoration(color: iOweThis ? Colors.redAccent : const Color(0xFF00897B), borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(contra.groupName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            Text(iOweThis ? 'You owe' : 'Owes you', style: const TextStyle(color: Colors.black38, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text('₹${formatAmount(contra.balance.abs())}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            const Divider(height: 1),
            const SizedBox(height: 32),
            
            // Payment Actions
            if (isIowe) ...[
              if (widget.friend.upiId != null && widget.friend.upiId!.isNotEmpty) ...[
                if (!_paymentInitiated) ...[

                ] else ...[
                  const Icon(Icons.check_circle_outline, color: kPrimaryBlue, size: 48),
                  const SizedBox(height: 16),
                  const Text('Payment App Launched', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Confirm here once you finish the transfer.', style: TextStyle(color: Colors.black45, fontSize: 13)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isProcessing ? null : _settleAll,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isProcessing 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Confirm & Settle All', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _paymentInitiated = false),
                    child: const Text('Go back', style: TextStyle(color: Colors.black38)),
                  ),
                ],
              ] else ...[
                const AppSurface(
                  padding: EdgeInsets.all(16),
                  color: Color(0x0A000000),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      SizedBox(width: 12),
                      Expanded(child: Text('Friend hasn\'t set up a UPI ID yet.', style: TextStyle(fontSize: 12, color: Colors.black54))),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isProcessing ? null : _settleAll,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    child: const Text('Record Payment'),
                  ),
                ),
              ],
            ] else ...[
              // Receiver Side
              if (widget.currentProfile.hasUpiId) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _shareMyUpi,
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Share Link'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _isProcessing ? null : _settleAll,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isProcessing 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Confirm Receipt', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // No UPI set for me
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isProcessing ? null : _settleAll,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    child: const Text('Confirm Receipt'),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            const Text(
              'Recording this will settle the net balance across all groups listed above.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black38, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settleAll() async {
    setState(() => _isProcessing = true);
    final appState = context.read<AppState>();
    
    // Logic: If on net I am receiving money (or square), I (the receiver) am recording this.
    // Thus, all individual transactions should be auto-confirmed (handshaked).
    // If on net I am paying, I am recording an outbound payment, so all should stay pending.
    final globalNet = widget.friend.netBalance;
    final isIoweGlobal = globalNet > 0.005;
    final shouldConfirmAll = !isIoweGlobal;

    try {
      for (final contra in widget.friend.contributions) {
        final fromId = contra.balance > 0 ? contra.myMemberId : contra.friendMemberId;
        final toId = contra.balance > 0 ? contra.friendMemberId : contra.myMemberId;
        
        final isIoweThisGroup = contra.balance > 0;

        await appState.addSettlement(
          groupId: contra.groupId,
          record: SettlementRecord(
            id: '',
            fromMemberId: fromId,
            toMemberId: toId,
            fromName: isIoweThisGroup ? widget.currentProfile.displayName : widget.friend.name,
            toName: isIoweThisGroup ? widget.friend.name : widget.currentProfile.displayName,
            amount: contra.balance.abs(),
            settledAt: DateTime.now(),
            status: shouldConfirmAll ? SettlementStatus.confirmed : SettlementStatus.pending,
            createdBy: widget.currentProfile.uid,
          ),
          confirmed: shouldConfirmAll,
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handlePay(String upiId, String name, double amount) async {
    final launched = await _launchUpi(upiId, name, amount);
    if (launched && mounted) {
      setState(() => _paymentInitiated = true);
    }
  }

  Future<void> _shareMyUpi() async {
    final net = widget.friend.netBalance.abs();
    final url = 'upi://pay?pa=${widget.currentProfile.upiId}&pn=${Uri.encodeComponent(widget.currentProfile.displayName)}&am=${formatAmount(net)}&cu=INR';
    final message = 'Hey ${widget.friend.name}, please pay ₹${formatAmount(net)} for our shared expenses on Bharat Dues. You can pay here: $url';
    await Share.share(message, subject: 'Payment Request');
  }

  Future<bool> _launchUpi(String upiId, String name, double amount) async {
    final url = Uri.parse('upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=${formatAmount(amount)}&cu=INR');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
      return true;
    } else {
      Clipboard.setData(ClipboardData(text: upiId));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UPI ID copied to clipboard')));
      return false;
    }
  }
}

class _SettleQrBox extends StatelessWidget {
  const _SettleQrBox({required this.upiId, required this.name, required this.amount});
  final String upiId;
  final String name;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: QrImageView(
          data: 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=${formatAmount(amount)}&cu=INR',
          version: QrVersions.auto,
          size: 160.0,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: kDarkBlue),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: kDarkBlue),
        ),
      ),
    );
  }
}

class _HomeActivityTab extends StatelessWidget {
  const _HomeActivityTab({
    required this.user,
    required this.profile,
    required this.appState,
  });

  final User user;
  final UserProfile profile;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SettlementGroup>>(
      stream: appState.groupsWithDeletedStream(uid: profile.uid, phoneNumber: profile.phoneNumber),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: kPrimaryBlue)));
        }

        final allGroups = snapshot.data ?? [];
        if (allGroups.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text('No group activities to show.', style: TextStyle(color: Colors.black38)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading(
              title: 'Activity',
              subtitle: 'Track your groups and restorations.',
            ),
            const SizedBox(height: 14),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allGroups.length,
              itemBuilder: (context, index) {
                final group = allGroups[index];
                return _GlobalActivityCard(group: group, appState: appState, currentProfile: profile);
              },
            ),
          ],
        );
      },
    );
  }
}

class _GlobalActivityCard extends StatelessWidget {
  const _GlobalActivityCard({required this.group, required this.appState, required this.currentProfile});
  final SettlementGroup group;
  final AppState appState;
  final UserProfile currentProfile;

  @override
  Widget build(BuildContext context) {
    final isDeleted = group.isDeleted;
    final timestamp = isDeleted ? (group.updatedAt ?? group.createdAt ?? DateTime.now()) : (group.createdAt ?? DateTime.now());
    
    final actor = group.lastActionBy ?? 'Someone';
    final actionName = group.lastActionType ?? (isDeleted ? 'deleted' : 'created');
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getBgColor(actionName),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIcon(actionName),
                color: _getIconColor(actionName),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: kDarkBlue, height: 1.4),
                      children: [
                        TextSpan(text: actor, style: const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: ' $actionName ', style: const TextStyle(fontWeight: FontWeight.w400, color: Colors.black54)),
                        TextSpan(text: '"${group.name}"', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatDateTime(timestamp),
                        style: const TextStyle(color: Colors.black45, fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      const Text('•', style: TextStyle(color: Colors.black12, fontSize: 10)),
                      const SizedBox(width: 8),
                      Text(
                        '${group.members.length} members',
                        style: const TextStyle(color: Colors.black38, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isDeleted)
              TextButton.icon(
                onPressed: () {
                  appState.restoreGroup(group.id, currentProfile.displayName);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Restored "${group.name}"')),
                  );
                },
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restore', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(foregroundColor: kPrimaryBlue),
              ),
          ],
        ),
      ),
    );
  }

  Color _getBgColor(String type) {
    if (type == 'deleted') return Colors.redAccent.withValues(alpha: 0.1);
    if (type == 'restored') return const Color(0xFF00A381).withValues(alpha: 0.1);
    return kPrimaryBlue.withValues(alpha: 0.1);
  }

  Color _getIconColor(String type) {
    if (type == 'deleted') return Colors.redAccent;
    if (type == 'restored') return const Color(0xFF00A381);
    return kPrimaryBlue;
  }

  IconData _getIcon(String type) {
    if (type == 'deleted') return Icons.delete_sweep_outlined;
    if (type == 'restored') return Icons.settings_backup_restore_rounded;
    return Icons.add_home_work_outlined;
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final m = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$m $ampm';
    
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today, $timeStr';
    }
    
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday, $timeStr';
    }
    
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}, $timeStr';
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
          profile: profile,
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
    required this.profile,
    required this.currentUserId,
    required this.onOpen,
    required this.onDelete,
  });

  final SettlementGroup group;
  final UserProfile profile;
  final String currentUserId;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    String displayName = group.name;

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(15),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: group.isNonGroup 
                    ? const Color(0xFF2D3748) 
                    : kPrimaryBlue.withValues(alpha: 0.1),
                border: Border.all(
                  color: group.isNonGroup 
                      ? Colors.white10 
                      : kPrimaryBlue.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                group.isNonGroup ? Icons.person_outline : Icons.groups_outlined, 
                color: group.isNonGroup ? Colors.black54 : kPrimaryBlue, 
                size: 24
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: kDarkBlue)),
                  const SizedBox(height: 4),
                  Text(
                    '${group.members.length} members',
                    style: const TextStyle(color: Colors.black38, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupSettlementScreen(
                      group: group, 
                      profile: profile,
                      initiallyOpenAddExpense: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add_circle_outline_rounded, color: kPrimaryBlue, size: 24),
              tooltip: 'Add Expense',
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.black12, size: 14),
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
        Text(label, style: const TextStyle(color: Colors.black38, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(amount, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
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
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black38),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.black38, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCreate,
      borderRadius: BorderRadius.circular(15),
      child: AppSurface(
        child: const Column(
          children: [
            Icon(Icons.groups_3_outlined, size: 32, color: kPrimaryBlue),
            const SizedBox(height: 12),
            const Text('No groups yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kDarkBlue)),
            const SizedBox(height: 4),
            const Text('Groups are perfect for trips and housemates.', style: TextStyle(color: Colors.black54), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
