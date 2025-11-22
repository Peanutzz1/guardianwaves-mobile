import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';

class AdminAccessRequestsScreen extends StatefulWidget {
  const AdminAccessRequestsScreen({super.key});

  @override
  State<AdminAccessRequestsScreen> createState() =>
      _AdminAccessRequestsScreenState();
}

class _AdminAccessRequestsScreenState extends State<AdminAccessRequestsScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<AccessRequestSummary> _requests = const [];
  List<AccessRequestSummary> _filteredRequests = const [];
  String _searchQuery = '';
  String? _statusFilter; // null = all, 'pending' = pending, 'approved' = approved

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await FirebaseFirestore.instance
            .collection('vesselAccessRequests')
            .orderBy('requestedAt', descending: true)
            .get();
      } catch (_) {
        snapshot = await FirebaseFirestore.instance
            .collection('vesselAccessRequests')
            .get();
      }

      final requests =
          snapshot.docs.map(AccessRequestSummary.fromSnapshot).toList()
            ..sort((a, b) {
              final aDate =
                  a.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  b.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });

      setState(() {
        _requests = requests;
        _applyFilters();
      });
    } catch (error) {
      setState(() {
        _errorMessage =
            'Failed to load access requests. Please try again later.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    _filteredRequests = _requests.where((request) {
      // Apply status filter
      if (_statusFilter != null) {
        if (_statusFilter == 'pending' && !request.isPending) {
          return false;
        }
        if (_statusFilter == 'approved' && !request.isApproved) {
          return false;
        }
      }

      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesVesselName =
            request.vesselName.toLowerCase().contains(query);
        final matchesEmail =
            request.requesterEmail.toLowerCase().contains(query);
        if (!matchesVesselName && !matchesEmail) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  int get _pendingCount => _requests.where((r) => r.isPending).length;
  int get _approvedCount => _requests.where((r) => r.isApproved).length;
  int get _declinedCount => _requests.where((r) => r.isDeclined).length;
  int get _totalCount => _requests.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Requests'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadRequests,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _ErrorState(message: _errorMessage!, onRetry: _loadRequests)
            : Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by vessel name or email...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _applyFilters();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                  // Filter buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _FilterButton(
                            label: 'All',
                            count: _totalCount,
                            isSelected: _statusFilter == null,
                            onTap: () {
                              setState(() {
                                _statusFilter = null;
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _FilterButton(
                            label: 'Pending',
                            count: _pendingCount,
                            isSelected: _statusFilter == 'pending',
                            onTap: () {
                              setState(() {
                                _statusFilter = 'pending';
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _FilterButton(
                            label: 'Approved',
                            count: _approvedCount,
                            isSelected: _statusFilter == 'approved',
                            onTap: () {
                              setState(() {
                                _statusFilter = 'approved';
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Request list
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_filteredRequests.isEmpty)
                          const _EmptyState()
                        else
                          ..._filteredRequests.map(_buildRequestCard),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRequestCard(AccessRequestSummary request) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF5135D5).withOpacity(0.12),
                  child: const Icon(Icons.vpn_key, color: Color(0xFF5135D5)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.vesselName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A4D68),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.requesterEmail,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  request.requestedAt != null
                      ? DateFormat(
                          'dd MMM yyyy • hh:mm a',
                        ).format(request.requestedAt!)
                      : 'Request date unavailable',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: request.isPending
                        ? () => _approveRequest(request)
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: request.isPending
                        ? () => _declineRequest(request)
                        : null,
                    icon: const Icon(Icons.close),
                    label: const Text('Decline'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE57373),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveRequest(AccessRequestSummary request) async {
    try {
      // Log request details for debugging
      debugPrint('=== APPROVING REQUEST ===');
      debugPrint('Request ID: ${request.id}');
      debugPrint('Vessel Name: ${request.vesselName}');
      debugPrint('Vessel ID: ${request.vesselId}');
      debugPrint('Requester Email: ${request.requesterEmail}');
      debugPrint('Requester ID: ${request.requesterId}');
      debugPrint('Requester ID is null: ${request.requesterId == null}');
      debugPrint('Requester ID is empty: ${request.requesterId?.isEmpty ?? true}');

      final requestRef = FirebaseFirestore.instance
          .collection('vesselAccessRequests')
          .doc(request.id);

      // Verify the request document exists before proceeding
      debugPrint('Checking if request document exists...');
      final requestDoc = await requestRef.get();
      if (!requestDoc.exists) {
        debugPrint('ERROR: Request document does not exist: ${request.id}');
        throw Exception('Request document does not exist: ${request.id}');
      }
      debugPrint('Request document exists ✓');

      final batch = FirebaseFirestore.instance.batch();

      // Update the request status
      debugPrint('Adding request status update to batch...');
      batch.update(requestRef, {
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      // Check if requesterId is missing
      if (request.requesterId == null || request.requesterId!.isEmpty) {
        debugPrint('WARNING: requesterId is missing or empty');
        debugPrint('Proceeding with request approval only (without client update)');
        
        // Still commit the batch to update the request status
        debugPrint('Committing batch (request update only)...');
        await batch.commit();
        debugPrint('Batch commit successful!');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Request approved, but client access not updated (missing requester ID).',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }

        setState(() {
          _requests = _requests
              .map(
                (item) => item.id == request.id
                    ? item.copyWith(status: 'approved')
                    : item,
              )
              .toList();
          _applyFilters();
        });
        return;
      }

      // Get client document
      final clientRef = FirebaseFirestore.instance
          .collection('client')
          .doc(request.requesterId);
      
      debugPrint('Fetching client document: ${request.requesterId}');
      final clientDoc = await clientRef.get();

      // Check if client document exists
      if (!clientDoc.exists) {
        debugPrint('ERROR: Client document does not exist: ${request.requesterId}');
        debugPrint('This will cause batch commit to fail!');
        throw Exception(
          'Client document not found for requester ID: ${request.requesterId}. '
          'Cannot grant vessel access.',
        );
      }

      debugPrint('Client document found ✓');
      debugPrint('Updating vesselAccess array...');

      final data = clientDoc.data() ?? <String, dynamic>{};
      final List<dynamic> accessList = List<dynamic>.from(
        data['vesselAccess'] ?? const [],
      );

      final existingIndex = accessList.indexWhere((entry) {
        if (entry is! Map) return false;
        if (request.vesselId != null && request.vesselId!.isNotEmpty) {
          return entry['vesselId'] == request.vesselId;
        }
        return entry['requestId'] == request.id &&
            entry['vesselName'] == request.vesselName;
      });

      final accessEntry = {
        'requestId': request.id,
        'vesselId': request.vesselId,
        'vesselName': request.vesselName,
        'isActive': true,
        'grantedBy': 'mobile_admin',
        'grantedAt': Timestamp.now(), // Use Timestamp.now() instead of FieldValue.serverTimestamp() for arrays
        'validUntil': null,
      };

      if (existingIndex >= 0) {
        debugPrint('Updating existing access entry at index $existingIndex');
        accessList[existingIndex] = {
          ...Map<String, dynamic>.from(accessList[existingIndex] as Map),
          ...accessEntry,
        };
      } else {
        debugPrint('Adding new access entry');
        accessList.add(accessEntry);
      }

      debugPrint('Adding client update to batch...');
      batch.update(clientRef, {
        'vesselAccess': accessList,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      debugPrint('Committing batch operation (request + client update)...');
      await batch.commit();
      debugPrint('Batch commit successful! ✓');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Access granted for ${request.vesselName}.'),
            backgroundColor: Colors.green,
          ),
        );
      }

      setState(() {
        _requests = _requests
            .map(
              (item) => item.id == request.id
                  ? item.copyWith(status: 'approved')
                  : item,
            )
            .toList();
        _applyFilters();
      });
    } catch (error, stackTrace) {
      // Comprehensive error logging
      debugPrint('=== ERROR APPROVING REQUEST ===');
      debugPrint('Error type: ${error.runtimeType}');
      debugPrint('Error message: $error');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('Request ID: ${request.id}');
      debugPrint('Requester ID: ${request.requesterId}');
      debugPrint('Vessel ID: ${request.vesselId}');
      debugPrint('Vessel Name: ${request.vesselName}');

      String errorMessage = 'Failed to approve request. Please try again.';
      
      // Provide specific error messages based on error type
      final errorStr = error.toString();
      if (errorStr.contains('Client document not found')) {
        errorMessage = 'Client account not found. Cannot grant access.';
      } else if (errorStr.contains('Request document does not exist')) {
        errorMessage = 'Request no longer exists. Please refresh the list.';
      } else if (errorStr.contains('permission-denied') || 
                 errorStr.contains('PERMISSION_DENIED')) {
        errorMessage = 'Permission denied. Check Firestore security rules.';
      } else if (errorStr.contains('not-found') || 
                 errorStr.contains('NOT_FOUND')) {
        errorMessage = 'Document not found. The request may have been deleted.';
      } else if (errorStr.contains('failed-precondition') ||
                 errorStr.contains('FAILED_PRECONDITION')) {
        errorMessage = 'Document was modified. Please refresh and try again.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _declineRequest(AccessRequestSummary request) async {
    try {
      final requestRef = FirebaseFirestore.instance
          .collection('vesselAccessRequests')
          .doc(request.id);

      await requestRef.update({
        'status': 'declined',
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${request.vesselName} request declined.')),
        );
      }

      setState(() {
        _requests = _requests
            .map(
              (item) => item.id == request.id
                  ? item.copyWith(status: 'declined')
                  : item,
            )
            .toList();
        _applyFilters();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline request. Please try again.'),
          ),
        );
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
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
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
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

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0A4D68)
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0A4D68)
                : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[700],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: count > 99 ? 6 : count > 9 ? 5 : 4,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.35)
                      : (label == 'Pending'
                          ? const Color(0xFFF2C94C).withOpacity(0.25)
                          : label == 'Approved'
                              ? const Color(0xFF27AE60).withOpacity(0.25)
                              : Colors.grey[400]!.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (label == 'Pending'
                            ? const Color(0xFFF2C94C)
                            : label == 'Approved'
                                ? const Color(0xFF27AE60)
                                : Colors.grey[800]),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
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
          Icon(Icons.mail_outline, size: 48, color: Colors.grey[500]),
          const SizedBox(height: 12),
          Text(
            'No access requests yet.',
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
