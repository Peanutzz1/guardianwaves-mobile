import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import 'vessel_detail_screen.dart';

class AdminVesselsScreen extends StatefulWidget {
  const AdminVesselsScreen({super.key});

  @override
  State<AdminVesselsScreen> createState() => _AdminVesselsScreenState();
}

class _AdminVesselsScreenState extends State<AdminVesselsScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  String _searchQuery = '';
  String _statusFilter = 'all';

  List<VesselSummary> _vessels = const [];

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
      final snapshot = await FirebaseFirestore.instance
          .collection('vessels')
          .get();

      final vessels =
          snapshot.docs
              .map(
                (doc) => VesselSummary.fromSnapshot(
                  doc as DocumentSnapshot<Map<String, dynamic>>,
                ),
              )
              .toList()
            ..sort((a, b) {
              final aTime =
                  a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

      setState(() {
        _vessels = vessels;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Failed to load vessels. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<VesselSummary> get _filteredVessels {
    return _vessels.where((vessel) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          vessel.name.toLowerCase().contains(_searchQuery) ||
          (vessel.imoNumber ?? '').toLowerCase().contains(_searchQuery) ||
          (vessel.companyName ?? '').toLowerCase().contains(_searchQuery);

      if (!matchesSearch) return false;

      if (_statusFilter == 'all') {
        return true;
      }

      return vessel.status == _statusFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Vessels'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadVessels,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _ErrorState(message: _errorMessage!, onRetry: _loadVessels)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSearchField(),
                  const SizedBox(height: 12),
                  _buildStatusChips(),
                  const SizedBox(height: 16),
                  if (_filteredVessels.isEmpty)
                    const _EmptyState()
                  else
                    ..._filteredVessels.map(_buildVesselCard),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search vessels...',
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

  Widget _buildStatusChips() {
    final chips = <Map<String, String>>[
      {'label': 'All', 'value': 'all'},
      {'label': 'Pending', 'value': 'pending'},
      {'label': 'Approved', 'value': 'approved'},
      {'label': 'Declined', 'value': 'declined'},
    ];

    return Wrap(
      spacing: 8,
      children: chips
          .map(
            (chip) => ChoiceChip(
              label: Text(chip['label']!),
              selected: _statusFilter == chip['value'],
              onSelected: (_) {
                setState(() {
                  _statusFilter = chip['value']!;
                });
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildVesselCard(VesselSummary vessel) {
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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A4D68),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (vessel.imoNumber != null &&
                              vessel.imoNumber!.isNotEmpty)
                            'IMO ${vessel.imoNumber}',
                          if (vessel.vesselType != null &&
                              vessel.vesselType!.isNotEmpty)
                            vessel.vesselType!.toUpperCase(),
                        ].join(' • '),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: vessel.status),
              ],
            ),
            const SizedBox(height: 12),
            if (vessel.companyName != null && vessel.companyName!.isNotEmpty)
              _infoRow(Icons.factory_outlined, 'Company', vessel.companyName!),
            if (vessel.master != null && vessel.master!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.person_outline, 'Master', vessel.master!),
            ],
            if (vessel.contactNumber != null &&
                vessel.contactNumber!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.phone, 'Contact', vessel.contactNumber!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  vessel.submittedAt != null
                      ? 'Submitted ${DateFormat('dd MMM yyyy').format(vessel.submittedAt!)}'
                      : 'Submission date unavailable',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _openVesselDetails(vessel),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Review Details'),
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
          Icon(Icons.sailing, size: 48, color: Colors.grey[500]),
          const SizedBox(height: 12),
          Text(
            'No vessels found for this filter.',
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
