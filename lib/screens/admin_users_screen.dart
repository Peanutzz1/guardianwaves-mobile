import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Screen for managing all client accounts from the admin app.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  String _searchQuery = '';
  String _statusFilter = 'all';

  List<_AdminUserSummary> _users = const [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final clientSnapshot = await FirebaseFirestore.instance
          .collection('client')
          .get();

      final List<_AdminUserSummary> result = [];

      for (final doc in clientSnapshot.docs) {
        final data = doc.data();

        if (data['isSoftDeleted'] == true) {
          continue;
        }

        final role = (data['role'] ?? 'client').toString().toLowerCase();
        if (role == 'admin' || role == 'super_admin') {
          continue;
        }

        result.add(
          _AdminUserSummary(
            id: doc.id,
            email: (data['email'] ?? '').toString(),
            displayName:
                (data['name'] ?? data['username'] ?? data['email'] ?? 'Client')
                    .toString(),
            role: role,
            accountStatus: (data['accountStatus'] ?? 'active')
                .toString()
                .toLowerCase(),
            createdAt: _parseTimestamp(data['createdAt']),
            isAdmin: false,
            vesselNames: _extractActiveVesselNames(data['vesselAccess']),
            rawData: Map<String, dynamic>.from(data),
          ),
        );
      }

      result.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      setState(() {
        _users = result;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Failed to load users. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<String> _extractActiveVesselNames(dynamic value) {
    if (value is! List) return const [];
    final names = <String>[];
    for (final entry in value) {
      if (entry is Map) {
        final isActive = entry['isActive'] == true;
        final vesselName = entry['vesselName']?.toString();
        if (isActive && vesselName != null && vesselName.isNotEmpty) {
          names.add(vesselName);
        }
      }
    }
    return names;
  }

  List<_AdminUserSummary> get _filteredUsers {
    return _users.where((user) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          user.displayName.toLowerCase().contains(_searchQuery) ||
          user.email.toLowerCase().contains(_searchQuery) ||
          user.vesselNames.any(
            (name) => name.toLowerCase().contains(_searchQuery),
          );

      if (!matchesSearch) return false;

      if (_statusFilter == 'all') {
        return true;
      }

      return user.accountStatus == _statusFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users Management'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadUsers,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _ErrorState(message: _errorMessage!, onRetry: _loadUsers)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSearchBar(theme),
                  const SizedBox(height: 12),
                  _buildStatusFilter(theme),
                  const SizedBox(height: 16),
                  if (_filteredUsers.isEmpty)
                    const _EmptyState()
                  else
                    ..._filteredUsers.map(_buildUserCard),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search clients...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (value) {
        setState(() {
          _searchQuery = value.trim().toLowerCase();
        });
      },
    );
  }

  Widget _buildStatusFilter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _statusFilter,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Statuses')),
            DropdownMenuItem(value: 'active', child: Text('Active')),
            DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
            DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _statusFilter = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildUserCard(_AdminUserSummary user) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF0A4D68).withOpacity(0.1),
                  child: Text(
                    user.initials,
                    style: const TextStyle(
                      color: Color(0xFF0A4D68),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A4D68),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: user.accountStatus),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TagChip(
                  label: user.isAdmin ? 'ADMIN' : 'CLIENT',
                  color: user.isAdmin
                      ? const Color(0xFF5135D5)
                      : const Color(0xFF088395),
                ),
                if (user.vesselNames.isNotEmpty)
                  _TagChip(
                    label:
                        '${user.vesselNames.length} vessel${user.vesselNames.length == 1 ? '' : 's'}',
                    color: const Color(0xFF0A4D68),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'Created: ${_formatDate(user.createdAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            if (user.vesselNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Vessels: ${user.vesselNames.join(', ')}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _ActionButton(
                  icon: Icons.visibility,
                  color: const Color(0xFF088395),
                  onPressed: () => _showUserDetails(user),
                ),
                const SizedBox(width: 12),
                if (!user.isAdmin)
                  _ActionButton(
                    icon: user.accountStatus == 'suspended'
                        ? Icons.play_arrow
                        : Icons.pause,
                    color: const Color(0xFFF2C94C),
                    onPressed: () => _toggleSuspendUser(user),
                  ),
                const SizedBox(width: 12),
                if (!user.isAdmin)
                  _ActionButton(
                    icon: Icons.delete,
                    color: const Color(0xFFE57373),
                    onPressed: () => _confirmDeleteUser(user),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSuspendUser(_AdminUserSummary user) async {
    final newStatus = user.accountStatus == 'suspended'
        ? 'active'
        : 'suspended';
    await _updateAccountStatus(user, newStatus);
  }

  Future<void> _confirmDeleteUser(_AdminUserSummary user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Account'),
        content: Text(
          'Are you sure you want to archive ${user.displayName}? '
          'They will lose access to the app until restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _softDeleteUser(user);
    }
  }

  Future<void> _updateAccountStatus(
    _AdminUserSummary user,
    String newStatus,
  ) async {
    try {
      final collection = user.isAdmin ? 'users' : 'client';
      final docRef = FirebaseFirestore.instance
          .collection(collection)
          .doc(user.id);

      await docRef.update({
        'accountStatus': newStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
        if (newStatus == 'suspended') 'isSuspended': true,
        if (newStatus != 'suspended') 'isSuspended': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.displayName} is now $newStatus.')),
        );
      }

      await _loadUsers();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update account. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _softDeleteUser(_AdminUserSummary user) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('client')
          .doc(user.id);

      await docRef.update({
        'accountStatus': 'inactive',
        'isSoftDeleted': true,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.displayName} has been archived.')),
        );
      }

      await _loadUsers();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to archive account. Please try again.'),
          ),
        );
      }
    }
  }

  void _showUserDetails(_AdminUserSummary user) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user.displayName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A4D68),
                ),
              ),
              const SizedBox(height: 8),
              _detailRow('Email', user.email),
              _detailRow('Role', user.role.toUpperCase()),
              _detailRow('Status', user.accountStatus.toUpperCase()),
              _detailRow('Created', _formatDate(user.createdAt)),
              if (user.vesselNames.isNotEmpty)
                _detailRow('Vessels', user.vesselNames.join(', ')),
              if (user.rawData['phoneNumber'] != null)
                _detailRow('Contact', user.rawData['phoneNumber'].toString()),
              if (user.rawData['company'] != null)
                _detailRow('Company', user.rawData['company'].toString()),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF0A4D68),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'N/A' : value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return DateFormat('dd/MM/yyyy').format(date);
  }
}

class _AdminUserSummary {
  const _AdminUserSummary({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.accountStatus,
    required this.isAdmin,
    required this.vesselNames,
    required this.rawData,
    this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final String accountStatus;
  final bool isAdmin;
  final DateTime? createdAt;
  final List<String> vesselNames;
  final Map<String, dynamic> rawData;

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    if (displayName.isNotEmpty) {
      return displayName.substring(0, 1).toUpperCase();
    }
    return 'U';
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'active':
        color = const Color(0xFF27AE60);
        break;
      case 'suspended':
        color = const Color(0xFFF2C94C);
        break;
      case 'inactive':
        color = const Color(0xFFE57373);
        break;
      default:
        color = const Color(0xFF828282);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 48, color: Colors.grey[500]),
          const SizedBox(height: 12),
          Text(
            'No users match your filters yet.',
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

DateTime? _parseTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;

  if (value is Map) {
    final seconds = value['seconds'];
    if (seconds is int) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
  }

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  return null;
}

