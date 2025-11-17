import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import 'add_vessel_screen_v2.dart';
import 'vessel_detail_screen.dart';

class VesselsScreen extends StatefulWidget {
  const VesselsScreen({super.key});

  @override
  State<VesselsScreen> createState() => _VesselsScreenState();
}

class _VesselsScreenState extends State<VesselsScreen> {
  String _searchQuery = '';
  String? _dateFilter; // For registration date filter
  String _normalizedStatus(Map<String, dynamic> data) {
    final rawStatus = data['submissionStatus'] ??
        data['status'] ??
        data['approvalStatus'] ??
        data['vesselStatus'] ??
        '';
    return rawStatus.toString().toLowerCase();
  }

  bool _isApprovedStatus(Map<String, dynamic> data) {
    return _normalizedStatus(data) == 'approved';
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
        .toLowerCase();
    return archivedStatus == 'archived';
  }

  bool _shouldDisplayVessel(Map<String, dynamic> data) {
    return _isApprovedStatus(data) && !_isSoftDeleted(data) && !_isArchived(data);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vessel Information'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final userId = authProvider.user?['uid'];
          final role = authProvider.user?['role']?.toString().toLowerCase() ?? 'client';
          final isAdmin = role == 'admin' || role == 'super_admin';

          if (!isAdmin && userId == null) {
            return const Center(child: Text('Not authenticated'));
          }

          Query<Map<String, dynamic>> query =
              FirebaseFirestore.instance.collection('vessels');

          if (!isAdmin) {
            query = query
                .where('userId', isEqualTo: userId)
                .where('submissionStatus', isEqualTo: 'approved');
          }

          // Create stream for accessible vessels (real-time)
          final accessibleVesselsStream = isAdmin || userId == null || userId.isEmpty
              ? Stream<List<DocumentSnapshot<Map<String, dynamic>>>>.value([])
              : _getAccessibleVesselsStream(userId);

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Stream for accessible vessels from user's vesselAccess array (real-time)
              return StreamBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
                stream: accessibleVesselsStream,
                builder: (context, accessibleSnapshot) {
                  // Show loading only if we have no owned vessels and accessible vessels are still loading
                  if (accessibleSnapshot.connectionState == ConnectionState.waiting && 
                      (!snapshot.hasData || snapshot.data!.docs.isEmpty)) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final ownedVessels = snapshot.hasData
                      ? snapshot.data!.docs
                          .map((doc) {
                            final data = doc.data();
                            final vessel = {
                              'id': doc.id,
                              ...data,
                              'isOwned': true,
                            };
                            return vessel;
                          })
                          .where(_shouldDisplayVessel)
                          .toList()
                      : <Map<String, dynamic>>[];

                  final accessibleVessels = accessibleSnapshot.hasData
                      ? accessibleSnapshot.data!
                          .map((doc) {
                            final data = doc.data();
                            if (data == null) {
                              return null;
                            }
                            final vessel = {
                              'id': doc.id,
                              ...data,
                              'isOwned': false,
                              'isAccessGranted': true,
                            };
                            return vessel;
                          })
                          .whereType<Map<String, dynamic>>()
                          .where(_shouldDisplayVessel)
                          .toList()
                      : <Map<String, dynamic>>[];

                  // Combine owned and accessible vessels, removing duplicates
                  final allVesselIds = <String>{};
                  final vessels = <Map<String, dynamic>>[];
                  
                  // Add owned vessels first
                  for (var vessel in ownedVessels) {
                    final vesselId = vessel['id'] as String;
                    if (!allVesselIds.contains(vesselId)) {
                      allVesselIds.add(vesselId);
                      vessels.add(vessel);
                    }
                  }
                  
                  // Add accessible vessels that aren't already owned
                  for (var vessel in accessibleVessels) {
                    final vesselId = vessel['id'] as String;
                    if (!allVesselIds.contains(vesselId)) {
                      allVesselIds.add(vesselId);
                      vessels.add(vessel);
                    }
                  }

                  if (vessels.isEmpty) {
                    return _buildEmptyState();
                  }
              
              // Filter vessels based on search and date
              final filteredVessels = vessels.where((vessel) {
                // Search filter
                if (_searchQuery.isNotEmpty) {
                  final searchLower = _searchQuery.toLowerCase();
                  final matches = (vessel['vesselName'] ?? '').toString().toLowerCase().contains(searchLower) ||
                                 (vessel['imoNumber'] ?? '').toString().toLowerCase().contains(searchLower) ||
                                 (vessel['vesselType'] ?? '').toString().toLowerCase().contains(searchLower) ||
                                 (vessel['master'] ?? '').toString().toLowerCase().contains(searchLower) ||
                                 (vessel['contactNumber'] ?? '').toString().toLowerCase().contains(searchLower);
                  if (!matches) return false;
                }
                
                // Date filter
                if (_dateFilter != null && _dateFilter!.isNotEmpty) {
                  try {
                    DateTime? vesselDate;
                    if (vessel['createdAt'] != null) {
                      if (vessel['createdAt'] is Timestamp) {
                        vesselDate = (vessel['createdAt'] as Timestamp).toDate();
                      } else if (vessel['createdAt'] is Map && vessel['createdAt']['seconds'] != null) {
                        vesselDate = DateTime.fromMillisecondsSinceEpoch(vessel['createdAt']['seconds'] * 1000);
                      }
                    }
                    
                    if (vesselDate != null) {
                      final filterDate = DateTime.parse(_dateFilter!);
                      if (vesselDate.year != filterDate.year ||
                          vesselDate.month != filterDate.month ||
                          vesselDate.day != filterDate.day) {
                        return false;
                      }
                    } else {
                      return false;
                    }
                  } catch (e) {
                    // If date parsing fails, include the vessel
                  }
                }
                
                return true;
              }).toList();

              // Calculate statistics
              final stats = _calculateStatistics(vessels);

              return Column(
                children: [
                  // Header Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vessel Information',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0A4D68),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Complete registry of maritime vessels with detailed specifications and compliance data',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Summary Cards
                  _buildSummaryCards(stats),
                  
                  // Search and Filter Section
                  _buildSearchAndFilterSection(),
                  
                  // Vessels Table
                  Expanded(
                    child: filteredVessels.isEmpty
                        ? _buildEmptyState()
                        : _buildVesselsTable(filteredVessels),
                  ),
                ],
              );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Creates a real-time stream of accessible vessels based on user's vesselAccess array
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>> _getAccessibleVesselsStream(
    String userId,
  ) {
    try {
      // Listen to user document changes in real-time
      return FirebaseFirestore.instance
          .collection('client')
          .doc(userId)
          .snapshots()
          .asyncMap((userDoc) async {
            if (!userDoc.exists) {
              return <DocumentSnapshot<Map<String, dynamic>>>[];
            }

            final userData = userDoc.data();
            final vesselAccess = userData?['vesselAccess'] as List? ?? [];

            if (vesselAccess.isEmpty) {
              return <DocumentSnapshot<Map<String, dynamic>>>[];
            }

            // Filter for active access entries with vesselId
            final activeAccess = vesselAccess.where((access) {
              if (access is! Map) return false;
              final isActive = access['isActive'] == true;
              final vesselId = access['vesselId'] as String?;
              final validUntil = access['validUntil'];
              
              // Check if access is still valid (if validUntil exists)
              if (validUntil != null) {
                try {
                  DateTime validUntilDate;
                  if (validUntil is Timestamp) {
                    validUntilDate = validUntil.toDate();
                  } else if (validUntil is String) {
                    validUntilDate = DateTime.parse(validUntil);
                  } else if (validUntil is Map && validUntil['seconds'] != null) {
                    validUntilDate = DateTime.fromMillisecondsSinceEpoch(
                        validUntil['seconds'] * 1000);
                  } else {
                    return false;
                  }
                  
                  if (validUntilDate.isBefore(DateTime.now())) {
                    return false; // Access has expired
                  }
                } catch (e) {
                  // If date parsing fails, assume access is still valid
                }
              }
              
              return isActive && vesselId != null && vesselId.isNotEmpty;
            }).toList();

            if (activeAccess.isEmpty) {
              return <DocumentSnapshot<Map<String, dynamic>>>[];
            }

            // Fetch vessels that user has access to
            final vesselIds = activeAccess
                .map((access) => (access as Map)['vesselId'] as String)
                .where((id) => id.isNotEmpty)
                .toList();

            if (vesselIds.isEmpty) {
              return <DocumentSnapshot<Map<String, dynamic>>>[];
            }

            // Fetch vessels in batches (Firestore 'in' query limit is 10)
            final List<DocumentSnapshot<Map<String, dynamic>>> allDocs = [];
            for (var i = 0; i < vesselIds.length; i += 10) {
              final batch = vesselIds.skip(i).take(10).toList();
              final query = FirebaseFirestore.instance
                  .collection('vessels')
                  .where(FieldPath.documentId, whereIn: batch);
              
              final snapshot = await query.get();
              allDocs.addAll(snapshot.docs);
            }

            return allDocs;
          }).handleError((error) {
            print('Error in accessible vessels stream: $error');
            return <DocumentSnapshot<Map<String, dynamic>>>[];
          });
    } catch (e) {
      print('Error creating accessible vessels stream: $e');
      return Stream.value(<DocumentSnapshot<Map<String, dynamic>>>[]);
    }
  }

  Map<String, int> _calculateStatistics(List<Map<String, dynamic>> vessels) {
    int validCertificates = 0;
    int expiredCertificates = 0;
    int expiringSoon = 0;
    int officersAndCrew = 0;

    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));

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

    for (var vessel in vessels) {
      // Count officers and crew
      final officersCrew = vessel['officersCrew'] as List? ?? [];
      officersAndCrew += officersCrew.length;

      // Check all certificate types with source tracking
      final certificates = [
        ...(vessel['certificates'] as List? ?? []).map((cert) => {...cert as Map, 'source': 'certificates'}),
        ...(vessel['expiryCertificates'] as List? ?? []).map((cert) => {...cert as Map, 'source': 'expiry'}),
        ...(vessel['competencyCertificates'] as List? ?? []).map((cert) => {...cert as Map, 'source': 'competency'}),
        ...(vessel['competencyLicenses'] as List? ?? []).map((cert) => {...cert as Map, 'source': 'license'}),
      ];

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
    }

    return {
      'validCertificates': validCertificates,
      'expiredCertificates': expiredCertificates,
      'expiringSoon': expiringSoon,
      'officersAndCrew': officersAndCrew,
    };
  }

  Widget _buildSummaryCards(Map<String, int> stats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[50],
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              stats['validCertificates'] ?? 0,
              'Valid Certificates',
              Icons.check_circle,
              Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              stats['expiredCertificates'] ?? 0,
              'Expired Certificates',
              Icons.cancel,
              Colors.red,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              stats['expiringSoon'] ?? 0,
              'Expiring Soon',
              Icons.warning_amber,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              stats['officersAndCrew'] ?? 0,
              'Officers and Crew',
              Icons.people,
              Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(int count, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          // Search Bar
          TextField(
            decoration: InputDecoration(
              hintText: 'Search vessels...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
          
          const SizedBox(height: 12),
          
          // Date Filter - Vertical layout for mobile
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _dateFilter != null ? DateTime.parse(_dateFilter!) : DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _dateFilter = DateFormat('yyyy-MM-dd').format(picked);
                });
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dateFilter != null && _dateFilter!.isNotEmpty
                          ? DateFormat('dd/MM/yyyy').format(DateTime.parse(_dateFilter!))
                          : 'Filter by Registration Date',
                      style: TextStyle(
                        fontSize: 14,
                        color: _dateFilter != null && _dateFilter!.isNotEmpty
                            ? Colors.black
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                  if (_dateFilter != null && _dateFilter!.isNotEmpty)
                    InkWell(
                      onTap: () {
                        setState(() => _dateFilter = null);
                      },
                      child: const Icon(Icons.clear, size: 18, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVesselsTable(List<Map<String, dynamic>> vessels) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: vessels.length,
      itemBuilder: (context, index) {
        final vessel = vessels[index];
        final isEven = index % 2 == 0;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isEven ? Colors.green[50] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green[700]!.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VesselDetailScreen(
                    vesselId: vessel['id'] ?? '',
                    vesselData: vessel,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row with Vessel Name and Type
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (vessel['vesselName'] ?? 'N/A').toString(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0A4D68),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                (vessel['vesselType'] ?? 'N/A').toString().toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Actions
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // View Button
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => VesselDetailScreen(
                                    vesselId: vessel['id'] ?? '',
                                    vesselData: vessel,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green[700],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.visibility,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Edit Button
                          InkWell(
                            onTap: () {
                              // Navigate to Add Vessel screen with edit mode
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddVesselScreenV2(
                                    vesselId: vessel['id'],
                                    vesselData: vessel,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Delete Button
                          InkWell(
                            onTap: () {
                              _showDeleteDialog(vessel);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const Divider(height: 24, thickness: 1),
                  
                  // Details Section
                  Row(
                    children: [
                      // Left Column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow('Station', 'CENT', Icons.location_on),
                            const SizedBox(height: 12),
                            _buildInfoRow('Master', (vessel['master'] ?? 'N/A').toString(), Icons.person),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Right Column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow('Contact', (vessel['contactNumber'] ?? 'N/A').toString(), Icons.phone),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDeleteDialog(Map<String, dynamic> vessel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vessel'),
        content: Text('Are you sure you want to delete ${(vessel['vesselName'] ?? 'this vessel').toString()}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // Implement delete logic here
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Delete functionality to be implemented')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sailing, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No approved vessels found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _dateFilter != null
                ? 'No vessels match your search criteria'
                : 'Vessels will appear here once they are approved',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      DateTime parsedDate;
      if (date is String) {
        parsedDate = DateTime.parse(date);
      } else if (date is Timestamp) {
        parsedDate = date.toDate();
      } else {
        return 'N/A';
      }
      
      final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${monthNames[parsedDate.month - 1]} ${parsedDate.day}, ${parsedDate.year}, '
             '${parsedDate.hour.toString().padLeft(2, '0')}:'
             '${parsedDate.minute.toString().padLeft(2, '0')} ${parsedDate.hour >= 12 ? 'PM' : 'AM'}';
    } catch (e) {
      return 'N/A';
    }
  }
}








