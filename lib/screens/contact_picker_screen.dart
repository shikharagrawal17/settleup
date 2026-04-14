import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../models/group_member.dart';
import '../providers/app_state.dart';

class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({super.key});

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  bool _loading = true;
  String? _error;
  List<Contact> _contacts = const [];
  String _query = '';
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted) {
        setState(() {
          _loading = false;
          _error = 'Contacts permission was denied.';
        });
        return;
      }

      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );

      setState(() {
        _contacts = contacts
            .where((contact) => contact.phones.isNotEmpty)
            .toList()
          ..sort(
            (first, second) => (first.displayName ?? '').compareTo(
              second.displayName ?? '',
            ),
          );
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _toggleSelection(Contact contact, bool selected) {
    final key = _contactKey(contact);
    setState(() {
      if (selected) {
        _selectedIds.add(key);
      } else {
        _selectedIds.remove(key);
      }
    });
  }

  void _done() {
    final selectedContacts =
        _contacts.where((contact) => _selectedIds.contains(_contactKey(contact)));
    final members = selectedContacts
        .map(
          (contact) => GroupMember(
            id: 'contact_${_contactKey(contact)}',
            name: contact.displayName ?? 'Unknown Contact',
            phoneNumber: contact.phones.isNotEmpty 
                ? AppState.normalisePhone(contact.phones.first.number) 
                : null,
            upiId: null,
          ),
        )
        .toList();

    Navigator.of(context).pop(members);
  }

  String _contactKey(Contact contact) {
    return contact.id ??
        '${contact.displayName ?? 'contact'}_${contact.phones.isNotEmpty ? contact.phones.first.number : 'no_phone'}';
  }

  List<Contact> get _filteredContacts {
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return _contacts;
    }

    return _contacts.where((contact) {
      final name = (contact.displayName ?? '').toLowerCase();
      final phone = contact.phones.isNotEmpty ? contact.phones.first.number.toLowerCase() : '';
      return name.contains(normalizedQuery) || phone.contains(normalizedQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Contacts'),
        actions: [
          TextButton(
            onPressed: _selectedIds.isEmpty ? null : _done,
            child: const Text('Add'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      onChanged: (value) {
                        setState(() {
                          _query = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Search contacts',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_filteredContacts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Text(
                          'No contacts match your search.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ..._filteredContacts.map((contact) {
                        final selected = _selectedIds.contains(_contactKey(contact));
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (value) => _toggleSelection(contact, value ?? false),
                          title: Text(contact.displayName ?? 'Unknown Contact'),
                          subtitle: Text(contact.phones.first.number),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      }),
                  ],
                ),
    );
  }
}
