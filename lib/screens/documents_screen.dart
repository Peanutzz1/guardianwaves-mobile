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
              value: _selectedVesselId != null && 
                     vesselOptions.any((item) => item.value == _selectedVesselId)
                ? _selectedVesselId
                : null,
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
                              doc.type == 'SIRB' && doc.crewName != null && doc.crewName!.isNotEmpty
                                  ? '${doc.name} - ${doc.crewName}'
                                  : doc.name,
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
          
          // For SIRB (officersCrew), use position as name and crew member name as crewName
          String documentName;
          String? crewName;
          if (defaultType == 'SIRB') {
            // For SIRB: name is position, crewName is the person's name
            documentName = (item['position'] ?? 
                           item['certificateType'] ?? 
                           'SIRB').toString();
            crewName = item['name'] as String?;
          } else {
            // For other documents: use standard name extraction
            documentName = (item['name'] ??
                           item['certificateType'] ??
                           item['licenseType'] ??
                           'Unnamed Document').toString();
            crewName = item['crewName'] as String?;
          }
          
          results.add(
            DocumentItem(
              id: '${vesselId}_${results.length}',
              name: documentName,
              type: (item['type'] ?? defaultType).toString(),
              category: category,
              vesselId: vesselId,
              vesselName: vesselName,
              expiryDate: item['expiryDate'] ??
                  item['dateExpiry'] ??
                  item['licenseExpiry'] ??
                  item['seafarerIdExpiry'],
              issuedDate: item['dateIssued'],
              fileUrl: _extractFileUrl(item, defaultType),
              hasExpiry: (item['hasExpiry'] as bool?) ??
                  item.containsKey('expiryDate') ||
                      item.containsKey('dateExpiry') ||
                      item.containsKey('licenseExpiry') ||
                      item.containsKey('seafarerIdExpiry'),
              crewName: crewName,
              photoUrls: _extractPhotoUrls(item),
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
        data['officersCrew'] as List<dynamic>?,
        defaultType: 'SIRB',
        category: 'Officers & Crew',
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
            doc.category.toLowerCase().contains(query) ||
            (doc.crewName != null && doc.crewName!.toLowerCase().contains(query));
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
    // Get all photo URLs - prefer photoUrls array, fallback to single fileUrl
    List<String> photoUrls = [];
    if (doc.photoUrls != null && doc.photoUrls!.isNotEmpty) {
      photoUrls = doc.photoUrls!;
    } else if (doc.fileUrl != null && doc.fileUrl!.isNotEmpty) {
      photoUrls = [doc.fileUrl!];
    }

    if (photoUrls.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file attached to this document.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show photo viewer dialog
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A4D68),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        photoUrls.length > 1
                            ? 'View Photos (${photoUrls.length})'
                            : 'View Photo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Photo content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: photoUrls.length == 1
                      ? _buildSinglePhotoView(photoUrls[0])
                      : _buildMultiplePhotosView(photoUrls),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSinglePhotoView(String url) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _showFullScreenPhoto(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 300,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 300,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 8),
                      const Text('Failed to load image'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open in browser'),
                        onPressed: () async {
                          try {
                            final uri = Uri.parse(url);
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiplePhotosView(List<String> urls) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${urls.length} photo(s) uploaded',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: urls.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _showFullScreenPhoto(urls[index], urls, index),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    urls[index],
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        alignment: Alignment.center,
                        child: const Icon(Icons.error_outline,
                            size: 32, color: Colors.red),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showFullScreenPhoto(String url, [List<String>? allUrls, int? index]) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenPhotoViewer(
          photoUrl: url,
          allPhotos: allUrls,
          initialIndex: index ?? 0,
        ),
      ),
    );
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

    // Reset time to start of day for accurate calculation (matching web app)
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfExpiry = DateTime(expiry.year, expiry.month, expiry.day);
    
    if (startOfExpiry.isBefore(startOfToday)) {
      return const ExpiryStatus(
        label: 'Expired',
        color: Colors.red,
        icon: Icons.error_outline,
      );
    }

    if (startOfExpiry.difference(startOfToday).inDays <= 30) {
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
    // Reset time to start of day for accurate calculation (matching web app)
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfExpiry = DateTime(expiry.year, expiry.month, expiry.day);
    
    Duration difference = startOfExpiry.difference(startOfToday);
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
      case 'sirb':
        return Icons.person_outlined;
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

  String? _extractFileUrl(Map<String, dynamic> item, [String? documentType]) {
    // For SIRB, check seafarerIdFileUrl first
    if (documentType == 'SIRB') {
      final keys = [
        'seafarerIdFileUrl',
        'certificateFileUrl',
        'fileUrl',
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
    } else {
      // For other documents, use standard keys
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
    }
    return null;
  }

  List<String>? _extractPhotoUrls(Map<String, dynamic> item) {
    // Check for photoUrls array first
    final photoUrls = item['photoUrls'];
    if (photoUrls is List) {
      final urls = photoUrls
          .where((url) => url is String && url.isNotEmpty)
          .cast<String>()
          .toList();
      if (urls.isNotEmpty) {
        return urls;
      }
    }
    // Fallback: if no photoUrls array, check for single fileUrl
    final fileUrl = _extractFileUrl(item);
    if (fileUrl != null && fileUrl.isNotEmpty) {
      return [fileUrl];
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

class _FullScreenPhotoViewer extends StatefulWidget {
  final String photoUrl;
  final List<String>? allPhotos;
  final int initialIndex;

  const _FullScreenPhotoViewer({
    required this.photoUrl,
    this.allPhotos,
    this.initialIndex = 0,
  });

  @override
  State<_FullScreenPhotoViewer> createState() => _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<_FullScreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.allPhotos ?? [widget.photoUrl];
    final hasMultiple = photos.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: hasMultiple
            ? Text(
                'Photo ${_currentIndex + 1} of ${photos.length}',
                style: const TextStyle(color: Colors.white),
              )
            : null,
      ),
      body: hasMultiple
          ? PageView.builder(
              controller: _pageController,
              itemCount: photos.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return _buildPhotoView(photos[index]);
              },
            )
          : _buildPhotoView(photos[0]),
    );
  }

  Widget _buildPhotoView(String url) {
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load image',
                      style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, color: Colors.white),
                    label: const Text('Open in browser',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      try {
                        final uri = Uri.parse(url);
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

