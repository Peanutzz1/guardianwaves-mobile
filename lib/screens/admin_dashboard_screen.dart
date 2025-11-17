import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import 'admin_access_requests_screen.dart';
import 'admin_review_screen.dart';
import 'admin_users_screen.dart';
import 'admin_vessels_screen.dart';
import 'vessel_detail_screen.dart';
import '../widgets/notification_icon_button.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  int _totalUsers = 0;
  int _totalAdmins = 0;
  int _totalClients = 0;
  int _totalVessels = 0;
  int _approvedVessels = 0;
  int _pendingApprovals = 0;
  int _pendingAccessRequests = 0;

  List<VesselSummary> _recentVessels = const [];
  List<VesselSummary> _pendingVessels = const [];
  List<AccessRequestSummary> _recentAccessRequests = const [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadUserStats(),
        _loadVesselStats(),
        _loadAccessRequests(),
      ]);
    } catch (error) {
      setState(() {
        _errorMessage = 'Failed to load dashboard data. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserStats() async {
    final clientSnapshot = await FirebaseFirestore.instance
        .collection('client')
        .get();
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .get();

    int adminCount = 0;
    for (final doc in usersSnapshot.docs) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString().toLowerCase();
      if (role == 'admin' || role == 'super_admin') {
        adminCount++;
      }
    }

    setState(() {
      _totalClients = clientSnapshot.size;
      _totalAdmins = adminCount;
      _totalUsers = clientSnapshot.size + adminCount;
    });
  }

  Future<void> _loadVesselStats() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('vessels')
        .get();

    final vessels = snapshot.docs.map(VesselSummary.fromSnapshot).toList()
      ..sort((a, b) {
        final aDate = a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    final pending = vessels.where((vessel) => vessel.isPending).toList();
    final approvedCount = vessels.where((vessel) => vessel.isApproved).length;

    setState(() {
      _totalVessels = vessels.length;
      _approvedVessels = approvedCount;
      _pendingApprovals = pending.length;
      _recentVessels = vessels.take(5).toList();
      _pendingVessels = pending;
    });
  }

  Future<void> _loadAccessRequests() async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await FirebaseFirestore.instance
          .collection('vesselAccessRequests')
          .orderBy('requestedAt', descending: true)
          .limit(8)
          .get();
    } catch (_) {
      snapshot = await FirebaseFirestore.instance
          .collection('vesselAccessRequests')
          .get();
    }

    final requests =
        snapshot.docs.map(AccessRequestSummary.fromSnapshot).toList()..sort((
          a,
          b,
        ) {
          final aDate = a.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

    setState(() {
      _pendingAccessRequests = requests
          .where((request) => request.isPending)
          .length;
      _recentAccessRequests = requests.take(5).toList();
    });
  }

  void _openManageUsers() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AdminUsersScreen()));
  }

  void _openManageVessels() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AdminVesselsScreen()));
  }

  void _openPendingApprovals() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AdminReviewScreen()))
        .then((_) => _loadDashboardData());
  }

  void _openAccessRequests() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => const AdminAccessRequestsScreen()),
        )
        .then((_) => _loadDashboardData());
  }

  void _openVesselDetails(VesselSummary vessel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VesselDetailScreen(
          vesselId: vessel.id,
          vesselData: {'id': vessel.id, ...vessel.rawData},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        actions: [
          const NotificationIconButton(),
          IconButton(
            onPressed: _isLoading ? null : _loadDashboardData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _ErrorState(message: _errorMessage!, onRetry: _loadDashboardData)
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardGreeting(
                        adminCount: _totalAdmins,
                        clientCount: _totalClients,
                      ),
                      const SizedBox(height: 20),
                      _SystemOverviewGrid(
                        totalUsers: _totalUsers,
                        adminCount: _totalAdmins,
                        clientCount: _totalClients,
                        totalVessels: _totalVessels,
                        approvedVessels: _approvedVessels,
                        pendingApprovals: _pendingApprovals,
                        pendingAccessRequests: _pendingAccessRequests,
                        onManageVessels: _openManageVessels,
                        onPendingApprovals: _openPendingApprovals,
                        onAccessRequests: _openAccessRequests,
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'Quick Actions',
                        subtitle: 'Access the most important admin workflows.',
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          _QuickActionCard(
                            icon: Icons.people_outline,
                            title: 'Manage Users',
                            subtitle:
                                'View and manage ${_formatCount(_totalUsers, 'user')}',
                            accentColor: const Color(0xFF0A99FF),
                            onTap: _openManageUsers,
                          ),
                          const SizedBox(height: 12),
                          _QuickActionCard(
                            icon: Icons.sailing_outlined,
                            title: 'Manage Vessels',
                            subtitle:
                                'Oversee ${_formatCount(_totalVessels, 'vessel')}',
                            accentColor: const Color(0xFF088395),
                            onTap: _openManageVessels,
                          ),
                          const SizedBox(height: 12),
                          _QuickActionCard(
                            icon: Icons.pending_actions_outlined,
                            title: 'Pending Approvals',
                            subtitle:
                                '${_formatCount(_pendingApprovals, 'submission')} awaiting review',
                            accentColor: const Color(0xFFF2C94C),
                            onTap: _openPendingApprovals,
                          ),
                          const SizedBox(height: 12),
                          _QuickActionCard(
                            icon: Icons.vpn_key,
                            title: 'Access Requests',
                            subtitle:
                                '${_formatCount(_pendingAccessRequests, 'request')} pending',
                            accentColor: const Color(0xFF7B61FF),
                            onTap: _openAccessRequests,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'Recent Vessels',
                        subtitle:
                            'Latest vessel submissions across the platform.',
                      ),
                      const SizedBox(height: 12),
                      if (_recentVessels.isEmpty)
                        const _EmptyState(
                          icon: Icons.directions_boat_outlined,
                          message: 'No recent vessel submissions.',
                        )
                      else
                        ..._recentVessels.map(
                          (vessel) => _RecentVesselCard(
                            vessel: vessel,
                            onTap: () => _openVesselDetails(vessel),
                          ),
                        ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'Pending Approvals',
                        subtitle:
                            'Quick snapshot of vessels waiting for review.',
                        actionLabel: 'View All',
                        onAction: _pendingVessels.isEmpty
                            ? null
                            : _openPendingApprovals,
                      ),
                      const SizedBox(height: 12),
                      if (_pendingVessels.isEmpty)
                        const _EmptyState(
                          icon: Icons.task_alt_outlined,
                          message: 'All caught up! No pending submissions.',
                        )
                      else
                        ..._pendingVessels
                            .take(3)
                            .map(
                              (vessel) => _PendingVesselPreview(
                                vessel: vessel,
                                onView: () => _openVesselDetails(vessel),
                              ),
                            )
                            .toList(),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'Access Requests',
                        subtitle: 'See who needs access to vessel information.',
                        actionLabel: 'Manage',
                        onAction: _recentAccessRequests.isEmpty
                            ? null
                            : _openAccessRequests,
                      ),
                      const SizedBox(height: 12),
                      if (_recentAccessRequests.isEmpty)
                        const _EmptyState(
                          icon: Icons.mail_outline,
                          message: 'No vessel access requests yet.',
                        )
                      else
                        ..._recentAccessRequests.map(
                          (request) => _AccessRequestTile(request: request),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  String _formatCount(int value, String singular) {
    final label = value == 1 ? singular : '${singular}s';
    return '$value $label';
  }
}

class _DashboardGreeting extends StatelessWidget {
  const _DashboardGreeting({
    required this.adminCount,
    required this.clientCount,
  });

  final int adminCount;
  final int clientCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2F73B5), Color(0xFF0A4D68)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, Administrator',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ) ??
                const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'System Administrator',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                  fontSize: 13.5,
                ) ??
                TextStyle(
                  fontSize: 13.5,
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _GreetingStatChip(
                  icon: Icons.admin_panel_settings,
                  label: 'Admins',
                  value: adminCount,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GreetingStatChip(
                  icon: Icons.people_alt,
                  label: 'Clients',
                  value: clientCount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _SystemOverviewGrid extends StatelessWidget {
  const _SystemOverviewGrid({
    required this.totalUsers,
    required this.adminCount,
    required this.clientCount,
    required this.totalVessels,
    required this.approvedVessels,
    required this.pendingApprovals,
    required this.pendingAccessRequests,
    this.onManageVessels,
    this.onPendingApprovals,
    this.onAccessRequests,
  });

  final int totalUsers;
  final int adminCount;
  final int clientCount;
  final int totalVessels;
  final int approvedVessels;
  final int pendingApprovals;
  final int pendingAccessRequests;
  final VoidCallback? onManageVessels;
  final VoidCallback? onPendingApprovals;
  final VoidCallback? onAccessRequests;

  @override
  Widget build(BuildContext context) {
    const spacing = 14.0;

    final cards = [
      _OverviewStatCard(
        icon: Icons.people_alt_outlined,
        title: 'Total Users',
        value: totalUsers.toString(),
        subtitle: '${_pluralize(clientCount, 'client')} / ${_pluralize(adminCount, 'admin')}',
        accentColor: const Color(0xFF0A99FF),
        onTap: onManageVessels, // Total Users -> Manage Vessels
      ),
      _OverviewStatCard(
        icon: Icons.directions_boat_filled_outlined,
        title: 'Total Vessels',
        value: totalVessels.toString(),
        subtitle: '$approvedVessels approved',
        accentColor: const Color(0xFF088395),
        onTap: onManageVessels, // Total Vessels -> Manage Vessels
      ),
      _OverviewStatCard(
        icon: Icons.pending_actions_outlined,
        title: 'Pending Vessels',
        value: pendingApprovals.toString(),
        subtitle: '${_pluralize(pendingApprovals, 'submission')} awaiting review',
        accentColor: const Color(0xFFF2C94C),
        onTap: onPendingApprovals, // Pending Vessels -> Admin Review
      ),
      _OverviewStatCard(
        icon: Icons.vpn_key_outlined,
        title: 'Access Requests',
        value: pendingAccessRequests.toString(),
        subtitle: '${_pluralize(pendingAccessRequests, 'request')} pending',
        accentColor: const Color(0xFF7B61FF),
        onTap: onAccessRequests, // Access Requests -> Access Request Screen
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columns = availableWidth >= 520
            ? 3
            : availableWidth >= 320
                ? 2
                : 1;
        final itemWidth = columns == 1
            ? availableWidth
            : (availableWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (card) => SizedBox(
                  width: itemWidth,
                  child: card,
                ),
              )
              .toList(),
        );
      },
    );
  }

  String _pluralize(int count, String singular) {
    final plural = count == 1 ? singular : '${singular}s';
    return '$count $plural';
  }
}

class _OverviewStatCard extends StatelessWidget {
  const _OverviewStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0A4D68),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0A4D68),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0A4D68),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentVesselCard extends StatelessWidget {
  const _RecentVesselCard({required this.vessel, required this.onTap});

  final VesselSummary vessel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF088395).withOpacity(0.12),
                    child: const Icon(
                      Icons.directions_boat,
                      color: Color(0xFF088395),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vessel.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0A4D68),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          vessel.submittedAt != null
                              ? DateFormat(
                                  'dd MMM yyyy · hh:mm a',
                                ).format(vessel.submittedAt!)
                              : 'Submission date unavailable',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(status: vessel.status),
                ],
              ),
              if (vessel.companyName != null &&
                  vessel.companyName!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.factory_outlined,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        vessel.companyName!,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingVesselPreview extends StatelessWidget {
  const _PendingVesselPreview({required this.vessel, required this.onView});

  final VesselSummary vessel;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vessel.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A4D68),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            vessel.submittedAt != null
                                ? DateFormat(
                                    'dd MMM yyyy',
                                  ).format(vessel.submittedAt!)
                                : 'Date unavailable',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _StatusPill(status: vessel.status),
              ],
            ),
            const SizedBox(height: 12),
            if (vessel.companyName != null &&
                vessel.companyName!.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(
                    Icons.business_center,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      vessel.companyName!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (vessel.master != null && vessel.master!.isNotEmpty)
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Master: ${vessel.master}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onView,
              child: const Text('Review Details'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessRequestTile extends StatelessWidget {
  const _AccessRequestTile({required this.request});

  final AccessRequestSummary request;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF7B61FF).withOpacity(0.12),
              child: const Icon(Icons.vpn_key, color: Color(0xFF7B61FF)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.vesselName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0A4D68),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    request.requesterEmail,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    request.requestedAt != null
                        ? DateFormat(
                            'dd MMM yyyy • hh:mm a',
                          ).format(request.requestedAt!)
                        : 'Requested date unavailable',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            _StatusPill(status: request.status),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status.toLowerCase()) {
      case 'approved':
        color = const Color(0xFF27AE60);
        label = 'APPROVED';
        break;
      case 'declined':
        color = const Color(0xFFE57373);
        label = 'DECLINED';
        break;
      default:
        color = const Color(0xFFF2C94C);
        label = 'PENDING';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A4D68),
                ),
              ),
            ),
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
        ],
      ],
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
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
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}




class _GreetingStatChip extends StatelessWidget {
  const _GreetingStatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}




