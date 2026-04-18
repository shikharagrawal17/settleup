import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';

import '../models/group_member.dart';
import '../providers/app_state.dart';

class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({super.key});

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> with SingleTickerProviderStateMixin {
  bool _loadingLocal = true;
  bool _loadingGoogle = false;
  String? _error;
  List<Contact> _localContacts = const [];
  String _query = '';
  final Set<String> _selectedIds = <String>{};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLocalContacts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalContacts() async {
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted) {
        setState(() {
          _loadingLocal = false;
          _error = 'Contacts permission was denied.';
        });
        return;
      }

      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );

      setState(() {
        _localContacts = contacts
            .where((contact) => contact.phones.isNotEmpty)
            .toList()
          ..sort(
            (first, second) => (first.displayName ?? '').compareTo(
              second.displayName ?? '',
            ),
          );
        _loadingLocal = false;
      });
    } catch (error) {
      setState(() {
        _loadingLocal = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadGoogleContacts() async {
    final appState = context.read<AppState>();
    setState(() => _loadingGoogle = true);
    await appState.fetchGoogleContacts();
    setState(() => _loadingGoogle = false);
  }

  void _toggleSelection(String key) {
    setState(() {
      if (_selectedIds.contains(key)) {
        _selectedIds.remove(key);
      } else {
        _selectedIds.add(key);
      }
    });
  }

  void _done() {
    final appState = context.read<AppState>();
    final List<GroupMember> selectedMembers = [];

    // Local
    for (final contact in _localContacts) {
      final key = 'local_${_contactKey(contact)}';
      if (_selectedIds.contains(key)) {
        selectedMembers.add(GroupMember(
          id: 'contact_${_contactKey(contact)}',
          name: contact.displayName ?? 'Unknown Contact',
          phoneNumber: contact.phones.isNotEmpty 
              ? AppState.normalisePhone(contact.phones.first.number) 
              : null,
        ));
      }
    }

    // Google
    for (final contact in appState.googleContacts) {
      final key = 'google_${contact.id}';
      if (_selectedIds.contains(key)) {
        selectedMembers.add(contact);
      }
    }

    Navigator.of(context).pop(selectedMembers);
  }

  String _contactKey(Contact contact) {
    return contact.id ??
        '${contact.displayName ?? 'contact'}_${contact.phones.isNotEmpty ? contact.phones.first.number : 'no_phone'}';
  }

  List<Contact> get _filteredLocalContacts {
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return _localContacts;

    return _localContacts.where((contact) {
      final name = (contact.displayName ?? '').toLowerCase();
      final phone = contact.phones.isNotEmpty ? contact.phones.first.number.toLowerCase() : '';
      return name.contains(normalizedQuery) || phone.contains(normalizedQuery);
    }).toList();
  }

  List<GroupMember> get _filteredGoogleContacts {
    final appState = context.read<AppState>();
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return appState.googleContacts;

    return appState.googleContacts.where((contact) {
      final name = contact.name.toLowerCase();
      final phone = (contact.phoneNumber ?? '').toLowerCase();
      return name.contains(normalizedQuery) || phone.contains(normalizedQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Contacts'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Device'),
            Tab(text: 'Google'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _selectedIds.isEmpty ? null : _done,
            child: const Text('Add'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: 'Search contacts',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Local Contacts
                _loadingLocal
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _filteredLocalContacts.isEmpty
                            ? const Center(child: Text('No device contacts found.'))
                            : ListView.builder(
                                itemCount: _filteredLocalContacts.length,
                                itemBuilder: (context, index) {
                                  final contact = _filteredLocalContacts[index];
                                  final key = 'local_${_contactKey(contact)}';
                                  final selected = _selectedIds.contains(key);
                                  return CheckboxListTile(
                                    value: selected,
                                    onChanged: (val) => _toggleSelection(key),
                                    title: Text(contact.displayName ?? 'Unknown'),
                                    subtitle: Text(contact.phones.first.number),
                                  );
                                },
                              ),
                
                // Google Contacts
                Column(
                  children: [
                    if (appState.googleContacts.isEmpty && !_loadingGoogle)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: FilledButton.icon(
                          onPressed: _loadGoogleContacts,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync Google Contacts'),
                        ),
                      ),
                    Expanded(
                      child: _loadingGoogle
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredGoogleContacts.isEmpty
                              ? const Center(child: Text('No Google contacts found.'))
                              : ListView.builder(
                                  itemCount: _filteredGoogleContacts.length,
                                  itemBuilder: (context, index) {
                                    final contact = _filteredGoogleContacts[index];
                                    final key = 'google_${contact.id}';
                                    final selected = _selectedIds.contains(key);
                                    return CheckboxListTile(
                                      value: selected,
                                      onChanged: (val) => _toggleSelection(key),
                                      title: Text(contact.name),
                                      subtitle: Text(contact.phoneNumber ?? 'No phone'),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
