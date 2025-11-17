import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import 'vessel_detail_screen.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<VesselSummary> _vessels = const [];
  int _totalFetched = 0;
  List<String> _debugLogs = const [];

  @override
  void initState() {
    super.initState();
    _loadVessels();
  }

  Future<void> _loadVessels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final query = FirebaseFirestore.instance.collection('vessels');

      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await query.orderBy('submittedAt', descending: true).get();
      } catch (_) {
        snapshot = await query.get();
      }

      final vessels = snapshot.docs
          .map(
            (doc) => VesselSummary.fromSnapshot(
              doc as DocumentSnapshot<Map<String, dynamic>>,
            ),
          )
          .toList();

      final pendingVessels = vessels.where((vessel) {
        final status = vessel.status;
        final submissionStatus =
            (vessel.rawData['submissionStatus'] ?? '').toString().toLowerCase();

        const pendingAliases = {
          'pending',
          'pending approval',
          'pending_approval',
          'for approval',
          'for_approval',
          'for review',
          'for_review',
          'awaiting_review',
          'awaiting approval',
          'awaiting_approval',
        };

        final isPending = vessel.isPending ||
            pendingAliases.contains(status) ||
            pendingAliases.contains(submissionStatus);

        return isPending;
      }).toList()
        ..sort((a, b) {
          final aTime = a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      final summaryLog =
          'AdminReview pending=${pendingVessels.length} total=${vessels.length}';
      debugPrint(summaryLog);
      // ignore: avoid_print
      print(summaryLog);

      final detailLogs = vessels
          .map(
            (vessel) =>
                '${vessel.name} → status=${vessel.status} '
                'submissionStatus=${(vessel.rawData['submissionStatus'] ?? '').toString()}',
          )
          .toList();

      for (final log in detailLogs) {
        debugPrint('AdminReview detail: $log');
        // ignore: avoid_print
        print('AdminReview detail: $log');
      }

      setState(() {
        _vessels = pendingVessels;
        _totalFetched = vessels.length;
        _debugLogs = [summaryLog, ...detailLogs];
      });
    } catch (error, stackTrace) {
      final errorLog = 'AdminReview error: $error';
      debugPrint(errorLog);
      // ignore: avoid_print
      print(errorLog);
      debugPrintStack(stackTrace: stackTrace);

      setState(() {
        _errorMessage = 'Failed to load vessels. Please try again.';
        _debugLogs = ['Error loading vessels: $error'];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Review'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadVessels,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _ErrorState(
                    message: _errorMessage!,
                    onRetry: _loadVessels,
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      if (_vessels.isEmpty) ...[
                        const _EmptyState(),
                        const SizedBox(height: 16),
                        _DebugLogPanel(logs: _debugLogs),
                      ] else
                        ..._vessels.map(_buildVesselCard),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Text(
      'Showing ${_vessels.length} pending submissions (fetched $_totalFetched)',
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0A4D68),
      ),
    );
  }

  Widget _buildVesselCard(VesselSummary vessel) {
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
                  backgroundColor: const Color(0xFF0A4D68).withOpacity(0.12),
                  child:
                      const Icon(Icons.directions_boat, color: Color(0xFF0A4D68)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vessel.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A4D68),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vessel.submittedAt != null
                            ? 'Submitted: ${DateFormat('MMM dd, yyyy, hh:mm a').format(vessel.submittedAt!)}'
                            : 'Submission date unavailable',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: vessel.status),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow(Icons.factory_outlined, 'Company',
                vessel.companyName ?? 'N/A'),
            const SizedBox(height: 8),
            _infoRow(Icons.person_outline, 'Master', vessel.master ?? 'N/A'),
            const SizedBox(height: 8),
            _infoRow(
              Icons.phone_android,
              'Contact',
              vessel.contactNumber ?? 'N/A',
            ),
            const SizedBox(height: 8),
            _infoRow(
              Icons.scale,
              'Gross Tonnage',
              vessel.grossTonnage != null
                  ? vessel.grossTonnage.toString()
                  : 'N/A',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _openVesselDetails(vessel),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Review Details'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _updateVesselStatus(vessel, 'approved'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Quick Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _updateVesselStatus(vessel, 'declined'),
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

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? 'N/A' : value,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _updateVesselStatus(
    VesselSummary vessel,
    String newStatus,
  ) async {
    try {
      final docRef =
          FirebaseFirestore.instance.collection('vessels').doc(vessel.id);

      await docRef.update({
        'submissionStatus': newStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
        'status': newStatus,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${vessel.name} marked as ${newStatus.toUpperCase()}.',
            ),
          ),
        );
      }

      setState(() {
        _vessels = _vessels
            .map(
              (item) => item.id == vessel.id
                  ? item.copyWith(
                      status: newStatus,
                      reviewedAt: DateTime.now(),
                    )
                  : item,
            )
            .where((item) => item.isPending)
            .toList();
        // Clear debug logs when approving a vessel
        if (newStatus == 'approved') {
          _debugLogs = [];
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update vessel. Please try again.'),
          ),
        );
      }
    }
  }

  void _openVesselDetails(VesselSummary vessel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VesselDetailScreen(
          vesselId: vessel.id,
          vesselData: {
            'id': vessel.id,
            ...vessel.rawData,
          },
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
            Text(
              message,
              textAlign: TextAlign.center,
            ),
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
          Icon(Icons.inbox, size: 48, color: Colors.grey[500]),
          const SizedBox(height: 12),
          Text(
            'No submissions found for this status.',
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

class _DebugLogPanel extends StatelessWidget {
  const _DebugLogPanel({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Debug info',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF0A4D68),
            ),
          ),
          const SizedBox(height: 8),
          ...logs.map(
            (log) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                log,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
