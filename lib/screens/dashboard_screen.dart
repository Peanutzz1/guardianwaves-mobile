import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../widgets/notification_icon_button.dart';
import 'certificate_scanner_screen.dart';
import 'add_vessel_screen_v2.dart';
import 'request_vessel_access_screen.dart';
import 'vessel_detail_screen.dart';
import 'documents_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  int _validCertificates = 0;
  int _expiredCertificates = 0;
  int _expiringSoon = 0;
  int _officersAndCrew = 0;
  List<Map<String, dynamic>> _userVessels = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?['uid'];
      
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() => _isLoading = true);
      
      // Add timeout to prevent infinite loading
      await Future.any([
        Future.delayed(const Duration(seconds: 10)),
        _fetchVesselStats(userId),
      ]);
    } catch (error) {
      print('Error loading stats: $error');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchVesselStats(String userId) async {
    try {

      // Get user's vessels from Firestore (using userId to match web app)
      final vesselsSnapshot = await FirebaseFirestore.instance
          .collection('vessels')
          .where('userId', isEqualTo: userId)
          .get();

      final now = DateTime.now();
      final thirtyDaysFromNow = now.add(const Duration(days: 30));

      int validCertificates = 0;
      int expiredCertificates = 0;
      int expiringSoon = 0;
      int officersAndCrew = 0;
      
      // Store user vessels for quick action
      List<Map<String, dynamic>> userVessels = [];

      // Helper function to parse expiry dates in various formats
      DateTime? parseExpiryDate(dynamic dateField) {
        if (dateField == null) return null;
        
        try {
          String dateStr = dateField.toString();
          
          // Parse date (handle dd/mm/yyyy format)
          if (dateStr.contains('/')) {
            final parts = dateStr.split('/');
            if (parts.length == 3) {
              return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
            }
          }
          
          return DateTime.parse(dateStr);
        } catch (e) {
          return null;
        }
      }

      for (var vesselDoc in vesselsSnapshot.docs) {
        final vesselData = vesselDoc.data();
        if (!_shouldIncludeVessel(vesselData)) {
          continue;
        }
        
        // Count officers and crew
        final officersCrew = vesselData['officersCrew'] as List? ?? [];
        officersAndCrew += officersCrew.length;
        
        // Check all certificate types with source tracking (matching vessels_screen.dart)
        final certificates = [
          ...(vesselData['certificates'] as List? ?? []).map((cert) => {...cert as Map, 'source': 'certificates'}),
          ...(vesselData['expiryCertificates'] as List? ?? []).map((cert) => {...cert as Map, 'source': 'expiry'}),
          ...(vesselData['competencyCertificates'] as List? ?? []).map((cert) => {...cert as Map, 'source': 'competency'}),
          ...(vesselData['competencyLicenses'] as List? ?? []).map((cert) => {...cert as Map, 'source': 'license'}),
        ];
        
        // Count certificates
        for (var cert in certificates) {
          // Determine which expiry field to check based on source, matching web app logic
          dynamic expiryDateField;
          if (cert['source'] == 'competency') {
            // COC certificates - check certificateExpiry first (what mobile app saves)
            expiryDateField = cert['certificateExpiry'] ?? 
                             cert['seafarerIdExpiry'] ?? 
                             cert['expiryDate'] ?? 
                             cert['dateExpiry'] ?? 
                             cert['dateExpiration'] ?? 
                             cert['expirationDate'];
          } else if (cert['source'] == 'license') {
            // License certificates
            expiryDateField = cert['licenseExpiry'] ?? 
                             cert['expiryDate'] ?? 
                             cert['dateExpiry'] ?? 
                             cert['dateExpiration'] ?? 
                             cert['expirationDate'];
          } else {
            // Other certificates (ship certificates)
            expiryDateField = cert['dateExpiry'] ?? 
                             cert['expiryDate'] ?? 
                             cert['dateExpiration'] ?? 
                             cert['expirationDate'];
          }

          if (expiryDateField == null || expiryDateField.toString().isEmpty) {
            // Certificates without expiry dates are considered valid
            validCertificates++;
            continue;
          }

          final expiryDate = parseExpiryDate(expiryDateField);
          
          if (expiryDate == null) {
            // Invalid date, count as valid
            validCertificates++;
            continue;
          }

          if (expiryDate.isBefore(now)) {
            expiredCertificates++;
          } else if (expiryDate.isBefore(thirtyDaysFromNow)) {
            expiringSoon++;
          } else {
            // Certificate is valid (not expired and not expiring within 30 days)
            validCertificates++;
          }
        }
        
        // Store vessel data
        userVessels.add({
          'id': vesselDoc.id,
          ...vesselData,
        });
      }

      setState(() {
        _validCertificates = validCertificates;
        _expiredCertificates = expiredCertificates;
        _expiringSoon = expiringSoon;
        _officersAndCrew = officersAndCrew;
        _userVessels = userVessels;
        _isLoading = false;
      });
    } catch (error) {
      print('Error fetching vessel stats: $error');
      setState(() {
        _isLoading = false;
        _validCertificates = 0;
        _expiredCertificates = 0;
        _expiringSoon = 0;
        _officersAndCrew = 0;
        _userVessels = [];
      });
    }
  }

  String _normalizedStatus(Map<String, dynamic> data) {
    final rawStatus = (data['submissionStatus'] ??
            data['status'] ??
            data['approvalStatus'] ??
            data['vesselStatus'] ??
            '')
        .toString();

    return rawStatus.replaceAll('_', ' ').trim().toLowerCase();
  }

  bool _isSoftDeleted(Map<String, dynamic> data) {
    return data['isSoftDeleted'] == true;
  }

  bool _isArchived(Map<String, dynamic> data) {
    if (data['isArchived'] == true || data['archived'] == true) {
      return true;
    }

    final archivedStatus = (data['archiveStatus'] ?? data['archivedStatus'] ?? '')
        .toString()
        .replaceAll('_', ' ')
        .trim()
        .toLowerCase();
    return archivedStatus == 'archived';
  }

  bool _isDeclinedStatus(String status) {
    const declinedStatuses = {
      'declined',
      'rejected',
      'denied',
      'void',
      'cancelled',
      'canceled',
    };

    return declinedStatuses.contains(status);
  }

  bool _shouldIncludeVessel(Map<String, dynamic> data) {
    if (_isSoftDeleted(data) || _isArchived(data)) {
      return false;
    }

    final status = _normalizedStatus(data);
    if (status.isEmpty) {
      return true;
    }

    if (_isDeclinedStatus(status)) {
      return false;
    }

    const allowedStatuses = {
      'approved',
      'pending',
      'pending approval',
      'pending review',
      'pending verification',
      'for approval',
      'for review',
      'awaiting approval',
      'awaiting review',
      'submitted',
      'under review',
      'in review',
      'active',
    };

    return allowedStatuses.contains(status);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: const [
          NotificationIconButton(),
          SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Welcome Section
                          Consumer<AuthProvider>(
                            builder: (context, authProvider, child) {
                              final username = authProvider.user?['username'] ?? 
                                             authProvider.user?['email'] ?? 'User';
                              final photoUrl = authProvider.user?['photoUrl'];
                              return Card(
                                color: const Color(0xFF088395),
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.white,
                                        radius: 30,
                                        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                                            ? NetworkImage(photoUrl) as ImageProvider
                                            : null,
                                        child: (photoUrl == null || photoUrl.isEmpty)
                                            ? Text(
                                                username[0].toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF088395),
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Welcome back,',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              username,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          
                          // Stats Grid
                          const Text(
                            'Overview',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0A4D68),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildStatsGrid(),
                          const SizedBox(height: 24),
                          
                          // Quick Actions
                          const Text(
                            'Quick Actions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0A4D68),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildQuickActions(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        _buildStatCard(
          title: 'Valid Certificates',
          value: _validCertificates.toString(),
          icon: Icons.verified,
          color: Colors.green,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DocumentsScreen(),
              ),
            );
          },
        ),
        _buildStatCard(
          title: 'Expired Certificates',
          value: _expiredCertificates.toString(),
          icon: Icons.error_outline,
          color: Colors.red,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DocumentsScreen(),
              ),
            );
          },
        ),
        _buildStatCard(
          title: 'Expiring Soon',
          value: _expiringSoon.toString(),
          icon: Icons.warning_amber,
          color: Colors.orange,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DocumentsScreen(),
              ),
            );
          },
        ),
        _buildStatCard(
          title: 'Officers and Crew',
          value: _officersAndCrew.toString(),
          icon: Icons.people,
          color: const Color(0xFF0A4D68),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DocumentsScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    // Check if user has vessels
    final hasVessels = _userVessels.isNotEmpty;
    final firstVessel = hasVessels ? _userVessels.first : null;
    
    return Column(
      children: [
        // Show "View My Vessel" if user has vessels, otherwise "Add New Vessel"
        hasVessels && firstVessel != null
            ? _buildActionCard(
                title: 'View My Vessel',
                subtitle: 'View and manage your vessel information and documents',
                icon: Icons.visibility,
                color: const Color(0xFF0A4D68),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VesselDetailScreen(
                        vesselId: firstVessel['id'] ?? '',
                        vesselData: firstVessel,
                      ),
                    ),
                  );
                },
              )
            : _buildActionCard(
                title: 'Add New Vessel',
                subtitle: 'Register a new vessel',
                icon: Icons.add_circle_outline,
                color: const Color(0xFF0A4D68),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddVesselScreenV2(),
                    ),
                  );
                },
              ),
        const SizedBox(height: 12),
        _buildActionCard(
          title: 'Request Vessel Access',
          subtitle: 'Request access to existing vessels',
          icon: Icons.handshake,
          color: const Color(0xFF088395),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RequestVesselAccessScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 28),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
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
