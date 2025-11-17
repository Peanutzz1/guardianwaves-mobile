import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/document_item.dart';
import '../providers/auth_provider.dart';
import 'document_renewal_dialog.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  String _searchQuery = '';
  String _selectedGroupBy = 'all';
  String? _selectedVesselId;

  final Map<String, bool> _expandedVessels = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          final user = authProvider.user;
          if (user == null || user['uid'] == null) {
            return const Center(child: Text('Not authenticated'));
          }

          final String userId = user['uid'] as String;
          final String userRole = (user['role'] as String?) ?? 'client';
          final bool isAdmin = userRole == 'admin' || userRole == 'super_admin';

          // Stream for owned vessels
          final Stream<QuerySnapshot<Map<String, dynamic>>> ownedVesselsStream =
              isAdmin
                  ? FirebaseFirestore.instance.collection('vessels').snapshots()
                  : FirebaseFirestore.instance
                      .collection('vessels')
                      .where('userId', isEqualTo: userId)
                      .snapshots();

          // Stream for accessible vessels (real-time)
          final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> accessibleVesselsStream = 
              isAdmin || userId.isEmpty
                  ? Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.value([])
                  : _getAccessibleVesselsStream(userId);

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ownedVesselsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Failed to load documents: ${snapshot.error}'),
                );
              }

              // Stream for accessible vessels
              return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                stream: accessibleVesselsStream,
                builder: (context, accessibleSnapshot) {
                  // Combine owned and accessible vessels
                  final ownedDocs = snapshot.data?.docs ?? [];
                  final accessibleDocs = accessibleSnapshot.data ?? [];
                  
                  // Remove duplicates by vessel ID
                  final allVesselIds = <String>{};
                  final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  
                  // Add owned vessels first
                  for (var doc in ownedDocs) {
                    if (!allVesselIds.contains(doc.id)) {
                      allVesselIds.add(doc.id);
                      allDocs.add(doc);
                    }
                  }
                  
                  // Add accessible vessels that aren't already owned
                  for (var doc in accessibleDocs) {
                    if (!allVesselIds.contains(doc.id)) {
                      allVesselIds.add(doc.id);
                      allDocs.add(doc);
                    }
                  }

                  if (allDocs.isEmpty) {
                    return _buildEmptyState();
                  }

                  final allDocuments = _extractDocuments(allDocs);
                  final filteredDocuments = _applyFilters(allDocuments);

              return Column(
                children: [
                  _buildSearchAndFilterBar(allDocs),
                  _buildGroupByChips(),
                  Expanded(
                    child: filteredDocuments.isEmpty
                        ? _buildEmptyDocumentsState()
                        : _buildDocumentsList(filteredDocuments, isAdmin),
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

  Widget _buildSearchAndFilterBar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> vessels,
  ) {
    final vesselOptions = vessels
        .map(
          (doc) => DropdownMenuItem<String?>(
            value: doc.id,
            child: Text(
              (doc.data()['vesselName'] as String?) ?? 'Unnamed vessel',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search documents...',
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
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
          if (vesselOptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _selectedVesselId,
              decoration: InputDecoration(
                labelText: 'Filter by vessel',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All vessels'),
                ),
                ...vesselOptions,
              ],
              onChanged: (value) {
                setState(() => _selectedVesselId = value);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupByChips() {
    const options = [
      ('all', 'All'),
      ('withExpiry', 'With Expiry'),
      ('noExpiry', 'No Expiry'),
      ('expired', 'Expired'),
      ('expiringSoon', 'Expiring Soon'),
      ('valid', 'Valid'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[50],
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final (value, label) = options[index];
          final bool isSelected = _selectedGroupBy == value;

          return FilterChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) {
              setState(() => _selectedGroupBy = value);
            },
            backgroundColor: Colors.white,
            selectedColor: const Color(0xFF0A4D68),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: options.length,
      ),
    );
  }

  Widget _buildDocumentsList(List<DocumentItem> documents, bool isAdmin) {
    final Map<String, List<DocumentItem>> grouped = {};
    for (final doc in documents) {
      grouped.putIfAbsent(doc.vesselId, () => []).add(doc);
    }

    final entries = grouped.entries.toList()
      ..sort(
        (a, b) => a.value.first.vesselName.compareTo(b.value.first.vesselName),
      );

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final vesselId = entry.key;
        final vesselName = entry.value.first.vesselName;
        final isExpanded = _expandedVessels[vesselId] ?? true;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedVessels[vesselId] = !isExpanded;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A4D68),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sailing, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vesselName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${entry.value.length} document${entry.value.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Column(
                  children: entry.value
                      .map((doc) => _buildDocumentCard(doc, isAdmin))
                      .toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDocumentCard(DocumentItem doc, bool isAdmin) {
    final expiryStatus = _getExpiryStatus(doc);
    final DateTime? expiryDate = _parseDate(doc.expiryDate);

    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: expiryStatus.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        expiryStatus.label,
        style: TextStyle(
          color: expiryStatus.color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: expiryStatus.color.withOpacity(0.15),
                        child: Icon(
                          _getDocumentIcon(doc.type),
                          color: expiryStatus.color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${doc.category} • ${doc.type}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            if (doc.hasExpiry && expiryDate != null)
                              Row(
                                children: [
                                  Icon(
                                    expiryStatus.icon,
                                    color: expiryStatus.color,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Expires ${_formatDate(expiryDate)} (${_formatExpiryDistance(expiryDate)})',
                                      style: TextStyle(
                                        color: expiryStatus.color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (!doc.hasExpiry)
                              const Text(
                                'No expiry date',
                                style: TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: statusBadge,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool stackButtons =
                      !isAdmin && constraints.maxWidth < 420;
                  final double buttonWidth = stackButtons
                      ? constraints.maxWidth
                      : (!isAdmin
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth);

                  Widget buildViewButton() {
                    return OutlinedButton.icon(
                      onPressed: doc.fileUrl == null
                          ? null
                          : () => _viewDocument(doc),
                      icon: const Icon(Icons.visibility),
                      label: const Text('View'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0A4D68),
                        side: const BorderSide(color: Color(0xFF0A4D68)),
                      ),
                    );
                  }

                  if (isAdmin) {
                    return SizedBox(
                      width: buttonWidth
                          .clamp(0, constraints.maxWidth)
                          .toDouble(),
                      child: buildViewButton(),
                    );
                  }

                  return Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: buttonWidth
                            .clamp(0, constraints.maxWidth)
                            .toDouble(),
                        child: buildViewButton(),
                      ),
                      SizedBox(
                        width: buttonWidth
                            .clamp(0, constraints.maxWidth)
                            .toDouble(),
                        child: ElevatedButton.icon(
                          onPressed: () => _updateDocument(doc),
                          icon: const Icon(Icons.update),
                          label: Text(
                            expiryStatus.label == 'Expired'
                                ? 'Renew'
                                : 'Update',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: expiryStatus.label == 'Expired'
                                ? Colors.red
                                : const Color(0xFF0A4D68),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 0),
          ],
        );
      },
    );
  }

  List<DocumentItem> _extractDocuments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> vessels,
  ) {
    final List<DocumentItem> results = [];

    for (final vessel in vessels) {
      final data = vessel.data();
      final vesselName = (data['vesselName'] as String?) ?? 'Unknown Vessel';
      final vesselId = vessel.id;

      void addDocumentFromList(
        List<dynamic>? rawList, {
        required String defaultType,
        required String category,
      }) {
        if (rawList == null) return;
        for (final item in rawList) {
          if (item is! Map<String, dynamic>) continue;
          results.add(
            DocumentItem(
              id: '${vesselId}_${results.length}',
              name: (item['name'] ??
                      item['certificateType'] ??
                      item['licenseType'] ??
                      'Unnamed Document')
                  .toString(),
              type: (item['type'] ?? defaultType).toString(),
              category: category,
              vesselId: vesselId,
              vesselName: vesselName,
              expiryDate: item['expiryDate'] ??
                  item['dateExpiry'] ??
                  item['licenseExpiry'] ??
                  item['seafarerIdExpiry'],
              issuedDate: item['dateIssued'],
              fileUrl: _extractFileUrl(item),
              hasExpiry: (item['hasExpiry'] as bool?) ??
                  item.containsKey('expiryDate') ||
                      item.containsKey('dateExpiry') ||
                      item.containsKey('licenseExpiry') ||
                      item.containsKey('seafarerIdExpiry'),
              crewName: item['crewName'] as String?,
            ),
          );
        }
      }

      addDocumentFromList(
        data['expiryCertificates'] as List<dynamic>?,
        defaultType: 'Certificate',
        category: 'Ship Certificates',
      );
      addDocumentFromList(
        data['competencyCertificates'] as List<dynamic>?,
        defaultType: 'Certificate of Competency',
        category: 'Officers & Crew',
      );
      addDocumentFromList(
        data['competencyLicenses'] as List<dynamic>?,
        defaultType: 'License',
        category: 'Officers & Crew',
      );
      addDocumentFromList(
        data['certificates'] as List<dynamic>?,
        defaultType: 'Certificate',
        category: 'General',
      );
      addDocumentFromList(
        data['documents'] as List<dynamic>?,
        defaultType: 'Document',
        category: 'Miscellaneous',
      );
    }

    return results;
  }

  List<DocumentItem> _applyFilters(List<DocumentItem> documents) {
    var filtered = List<DocumentItem>.from(documents);

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((doc) {
        return doc.name.toLowerCase().contains(query) ||
            doc.vesselName.toLowerCase().contains(query) ||
            doc.type.toLowerCase().contains(query) ||
            doc.category.toLowerCase().contains(query);
      }).toList();
    }

    if (_selectedVesselId != null) {
      filtered =
          filtered.where((doc) => doc.vesselId == _selectedVesselId).toList();
    }

    final DateTime now = DateTime.now();
    final DateTime thirtyDaysFromNow = now.add(const Duration(days: 30));

    switch (_selectedGroupBy) {
      case 'withExpiry':
        filtered = filtered
            .where((doc) => doc.hasExpiry && doc.expiryDate != null)
            .toList();
        break;
      case 'noExpiry':
        filtered = filtered
            .where((doc) => !doc.hasExpiry || doc.expiryDate == null)
            .toList();
        break;
      case 'expired':
        filtered = filtered.where((doc) {
          final expiry = _parseDate(doc.expiryDate);
          return doc.hasExpiry && expiry != null && expiry.isBefore(now);
        }).toList();
        break;
      case 'expiringSoon':
        filtered = filtered.where((doc) {
          final expiry = _parseDate(doc.expiryDate);
          return doc.hasExpiry &&
              expiry != null &&
              expiry.isAfter(now) &&
              expiry.isBefore(thirtyDaysFromNow);
        }).toList();
        break;
      case 'valid':
        filtered = filtered.where((doc) {
          final expiry = _parseDate(doc.expiryDate);
          return !doc.hasExpiry ||
              expiry == null ||
              expiry.isAfter(thirtyDaysFromNow);
        }).toList();
        break;
      default:
        break;
    }

    filtered.sort((a, b) {
      final expiryA = _parseDate(a.expiryDate);
      final expiryB = _parseDate(b.expiryDate);

      if (expiryA == null && expiryB == null) return 0;
      if (expiryA == null) return 1;
      if (expiryB == null) return -1;

      if (expiryA.isBefore(now) && expiryB.isAfter(now)) return -1;
      if (expiryA.isAfter(now) && expiryB.isBefore(now)) return 1;

      return expiryA.compareTo(expiryB);
    });

    return filtered;
  }

  Future<void> _viewDocument(DocumentItem doc) async {
    final url = doc.fileUrl;
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file attached to this document.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final uri = Uri.parse(url);
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the document.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening document: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateDocument(DocumentItem doc) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => DocumentRenewalDialog(
        document: doc,
        vesselId: doc.vesselId,
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _approveDocument(DocumentItem doc) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Approval flow is not configured for ${doc.name}.'),
      ),
    );
  }

  Future<void> _rejectDocument(DocumentItem doc) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Rejection flow is not configured for ${doc.name}.'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No vessels found. Add a vessel to start managing documents.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildEmptyDocumentsState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No documents match your filters.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  ExpiryStatus _getExpiryStatus(DocumentItem doc) {
    if (!doc.hasExpiry || doc.expiryDate == null) {
      return const ExpiryStatus(
        label: 'No Expiry',
        color: Colors.blueGrey,
        icon: Icons.remove_circle_outline,
      );
    }

    final expiry = _parseDate(doc.expiryDate);
    if (expiry == null) {
      return const ExpiryStatus(
        label: 'Unknown',
        color: Colors.grey,
        icon: Icons.help_outline,
      );
    }

    final now = DateTime.now();
    if (expiry.isBefore(now)) {
      return const ExpiryStatus(
        label: 'Expired',
        color: Colors.red,
        icon: Icons.error_outline,
      );
    }

    if (expiry.difference(now).inDays <= 30) {
      return const ExpiryStatus(
        label: 'Expiring Soon',
        color: Colors.orange,
        icon: Icons.warning_amber_outlined,
      );
    }

    return const ExpiryStatus(
      label: 'Valid',
      color: Colors.green,
      icon: Icons.check_circle_outline,
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;

    final String raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    try {
      if (raw.contains('/')) {
        final parts = raw.split('/');
        if (parts.length == 3) {
          final day = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final year = int.parse(parts[2]);
          return DateTime(year, month, day);
        }
      }
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _formatExpiryDistance(DateTime expiry) {
    final now = DateTime.now();
    Duration difference = expiry.difference(now);
    final bool isPast = difference.isNegative;
    difference = difference.abs();

    final int totalDays = difference.inDays;
    final int years = totalDays ~/ 365;
    final int months = (totalDays % 365) ~/ 30;
    final int days = totalDays % 30;
    final int hours = difference.inHours % 24;

    final List<String> parts = [];
    if (years > 0) {
      parts.add('$years year${years == 1 ? '' : 's'}');
    }
    if (months > 0) {
      parts.add('$months month${months == 1 ? '' : 's'}');
    }
    if (days > 0) {
      parts.add('$days day${days == 1 ? '' : 's'}');
    }
    if (parts.isEmpty && hours > 0) {
      parts.add('$hours hour${hours == 1 ? '' : 's'}');
    }
    if (parts.isEmpty) {
      parts.add('less than a day');
    }

    final String distance = parts.length > 1
        ? '${parts[0]}, ${parts[1]}${parts.length > 2 ? ', ${parts[2]}' : ''}'
        : parts[0];
    return isPast ? '$distance ago' : 'in $distance';
  }

  IconData _getDocumentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'license':
        return Icons.badge_outlined;
      case 'certificate of competency':
        return Icons.school_outlined;
      case 'document':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String? _extractFileUrl(Map<String, dynamic> item) {
    final keys = [
      'fileUrl',
      'certificateFileUrl',
      'url',
      'downloadURL',
      'cloudinaryUrl',
      'scannedFileUrl',
    ];

    for (final key in keys) {
      final value = item[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  /// Creates a real-time stream of accessible vessels based on user's vesselAccess array
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getAccessibleVesselsStream(
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
              return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            }

            final userData = userDoc.data();
            final vesselAccess = userData?['vesselAccess'] as List? ?? [];

            if (vesselAccess.isEmpty) {
              return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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
              return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            }

            // Fetch vessels that user has access to
            final vesselIds = activeAccess
                .map((access) => (access as Map)['vesselId'] as String)
                .where((id) => id.isNotEmpty)
                .toList();

            if (vesselIds.isEmpty) {
              return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            }

            // Fetch vessels in batches (Firestore 'in' query limit is 10)
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs = [];
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
            return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          });
    } catch (e) {
      print('Error creating accessible vessels stream: $e');
      return Stream.value(<QueryDocumentSnapshot<Map<String, dynamic>>>[]);
    }
  }
}

class ExpiryStatus {
  const ExpiryStatus({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}

