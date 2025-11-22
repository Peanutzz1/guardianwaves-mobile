import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../models/shipping_companies.dart';
import 'package:intl/intl.dart';

class DepartureLogScreen extends StatefulWidget {
  const DepartureLogScreen({super.key});

  @override
  State<DepartureLogScreen> createState() => _DepartureLogScreenState();
}

class _DepartureLogScreenState extends State<DepartureLogScreen> {
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _logTypeFilter; // null = all, 'arrival' = arrivals only, 'departure' = departures only
  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _filteredLogs = [];
  bool _showFormModal = false;
  Map<String, dynamic>? _editingLog;

  // Form controllers
  final TextEditingController _vesselNameController = TextEditingController();
  final TextEditingController _grossTonnageController = TextEditingController();
  final TextEditingController _netTonnageController = TextEditingController();
  final TextEditingController _shippingCompanyController = TextEditingController();
  final TextEditingController _captainNameController = TextEditingController();
  final TextEditingController _numberOfCrewController = TextEditingController();
  final TextEditingController _lastPortController = TextEditingController();
  final TextEditingController _nextPortController = TextEditingController();
  final TextEditingController _numberOfPassengersController = TextEditingController();
  final TextEditingController _rollingCargoController = TextEditingController();
  final TextEditingController _cargoOnboardController = TextEditingController();
  final TextEditingController _clearingOfficerNameController = TextEditingController();
  final TextEditingController _clearingOfficerContactController = TextEditingController();

  DateTime? _ata;
  DateTime? _etd;
  String? _selectedShippingCompany;
  bool _isSubmitting = false;
  String? _formError;
  bool _formSuccess = false;
  List<String> _shippingCompanyList = [];

  @override
  void initState() {
    super.initState();
    _loadShippingCompanies();
    _fetchLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _vesselNameController.dispose();
    _grossTonnageController.dispose();
    _netTonnageController.dispose();
    _shippingCompanyController.dispose();
    _captainNameController.dispose();
    _numberOfCrewController.dispose();
    _lastPortController.dispose();
    _nextPortController.dispose();
    _numberOfPassengersController.dispose();
    _rollingCargoController.dispose();
    _cargoOnboardController.dispose();
    _clearingOfficerNameController.dispose();
    _clearingOfficerContactController.dispose();
    super.dispose();
  }

  Future<void> _loadShippingCompanies() async {
    try {
      final companiesRef = FirebaseFirestore.instance
          .collection('shippingCompanies')
          .orderBy('name', descending: false);
      
      final snapshot = await companiesRef.get();
      List<String> companies = [];

      if (snapshot.docs.isNotEmpty) {
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['isSoftDeleted'] != true) {
            companies.add(data['name'] ?? data['companyName'] ?? '');
          }
        }
      }

      // If no companies in database, use predefined list
      if (companies.isEmpty) {
        companies = ShippingCompanies.companies.map((c) => c.name).toList();
      }

      companies.sort();
      setState(() {
        _shippingCompanyList = companies;
      });
    } catch (error) {
      print('Error loading shipping companies: $error');
      // Fallback to predefined list
      setState(() {
        _shippingCompanyList = ShippingCompanies.companies.map((c) => c.name).toList()..sort();
      });
    }
  }

  Future<void> _fetchLogs() async {
    try {
      setState(() => _isLoading = true);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?['uid'];

      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // For admin: fetch all logs; for regular users: filter by userId
      final logsRef = FirebaseFirestore.instance
          .collection('vesselArrivalDepartureLogs');
      
      // Check if user is admin
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final userRole = userDoc.data()?['role']?.toString().toLowerCase() ?? '';
      final isAdmin = userRole == 'admin' || userRole == 'super_admin';
      
      setState(() {
        _isAdmin = isAdmin;
      });
      
      // Fetch logs (sort in memory to avoid index requirements)
      final query = isAdmin 
          ? logsRef
          : logsRef.where('userId', isEqualTo: userId);
      
      final snapshot = await query.get();

      List<Map<String, dynamic>> logs = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        logs.add({
          'id': doc.id,
          ...data,
          'createdAt': data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          'ata': data['ata'] is Timestamp
              ? (data['ata'] as Timestamp).toDate()
              : (data['ata'] is String ? DateTime.tryParse(data['ata']) : null),
          'etd': data['etd'] is Timestamp
              ? (data['etd'] as Timestamp).toDate()
              : (data['etd'] is String ? DateTime.tryParse(data['etd']) : null),
        });
      }

      // Sort by creation date (newest first)
      logs.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));

      setState(() {
        _allLogs = logs;
        _filteredLogs = logs;
        _isLoading = false;
      });

      _searchController.addListener(_filterLogs);
    } catch (error) {
      print('Error fetching logs: $error');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading logs: $error')),
        );
      }
    }
  }

  void _filterLogs() {
    final searchTerm = _searchController.text.toLowerCase();
    setState(() {
      _filteredLogs = _allLogs.where((log) {
        // Type filter (arrival/departure)
        if (_logTypeFilter != null) {
          final actualMovementType = _getActualMovementType(log);
          if (actualMovementType != _logTypeFilter) return false;
        }

        // Search filter
        if (searchTerm.isNotEmpty) {
          final matchesSearch = 
              (log['vesselName']?.toString().toLowerCase().contains(searchTerm) ?? false) ||
              (log['shippingCompany']?.toString().toLowerCase().contains(searchTerm) ?? false) ||
              (log['captainName']?.toString().toLowerCase().contains(searchTerm) ?? false) ||
              (log['lastPort']?.toString().toLowerCase().contains(searchTerm) ?? false) ||
              (log['nextPort']?.toString().toLowerCase().contains(searchTerm) ?? false);
          if (!matchesSearch) return false;
        }

        // Date filter
        if (_startDate != null || _endDate != null) {
          final logDate = log['createdAt'] as DateTime?;
          if (logDate == null) return false;

          if (_startDate != null) {
            final startOfDay = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
            if (logDate.isBefore(startOfDay)) return false;
          }

          if (_endDate != null) {
            final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
            if (logDate.isAfter(endOfDay)) return false;
          }
        }

        return true;
      }).toList();
    });
  }

  void _openAddForm() {
    setState(() {
      _editingLog = null;
      _vesselNameController.clear();
      _grossTonnageController.clear();
      _netTonnageController.clear();
      _shippingCompanyController.clear();
      _captainNameController.clear();
      _numberOfCrewController.clear();
      _lastPortController.clear();
      _nextPortController.clear();
      _numberOfPassengersController.clear();
      _rollingCargoController.clear();
      _cargoOnboardController.clear();
      _clearingOfficerNameController.clear();
      _clearingOfficerContactController.clear();
      _ata = null;
      _etd = null;
      _selectedShippingCompany = null;
      _formError = null;
      _formSuccess = false;
      _showFormModal = true;
    });
  }

  void _openEditForm(Map<String, dynamic> log) {
    setState(() {
      _editingLog = log;
      _vesselNameController.text = log['vesselName'] ?? '';
      _grossTonnageController.text = log['grossTonnage'] ?? '';
      _netTonnageController.text = log['netTonnage'] ?? '';
      _shippingCompanyController.text = log['shippingCompany'] ?? '';
      _captainNameController.text = log['captainName'] ?? '';
      _numberOfCrewController.text = log['numberOfCrew']?.toString() ?? '';
      _lastPortController.text = log['lastPort'] ?? '';
      _nextPortController.text = log['nextPort'] ?? '';
      _numberOfPassengersController.text = log['numberOfPassengers'] ?? '';
      _rollingCargoController.text = log['rollingCargo'] ?? '';
      _cargoOnboardController.text = log['cargoOnboard'] ?? '';
      _clearingOfficerNameController.text = log['clearingOfficerName'] ?? '';
      _clearingOfficerContactController.text = log['clearingOfficerContact'] ?? '';
      _ata = log['ata'] is DateTime ? log['ata'] : null;
      _etd = log['etd'] is DateTime ? log['etd'] : null;
      _selectedShippingCompany = log['shippingCompany'];
      _formError = null;
      _formSuccess = false;
      _showFormModal = true;
    });
  }

  String? _validateForm() {
    if (_vesselNameController.text.trim().isEmpty) {
      return 'Vessel Name is required';
    }
    if (_shippingCompanyController.text.trim().isEmpty) {
      return 'Shipping Company is required';
    }
    if (_captainNameController.text.trim().isEmpty) {
      return 'Captain\'s Name is required';
    }

    // Check if it's an arrival log
    final isArrival = _lastPortController.text.trim().isNotEmpty || _ata != null;
    if (isArrival) {
      if (_lastPortController.text.trim().isEmpty) {
        return 'Last Port is required for Arrival logs';
      }
      if (_ata == null) {
        return 'ATA (Actual Time of Arrival) is required';
      }
    }

    if (_numberOfPassengersController.text.trim().isEmpty) {
      return 'Number of Passengers Onboard is required (use "Nil" if cargo-only)';
    }
    if (_clearingOfficerNameController.text.trim().isEmpty) {
      return 'Clearing Officer Name is required';
    }
    if (_clearingOfficerContactController.text.trim().isEmpty) {
      return 'Clearing Officer Contact Number is required';
    }

    return null;
  }

  Future<void> _submitForm() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }

    setState(() {
      _formError = null;
      _formSuccess = false;
      _isSubmitting = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?['uid'];
      final userName = authProvider.user?['displayName'] ?? 
                      authProvider.user?['username'] ?? 
                      authProvider.user?['email'] ?? 'User';

      // Auto-detect movement type
      String movementType = 'departure'; // default to departure
      if (_lastPortController.text.trim().isNotEmpty && _ata != null) {
        movementType = 'arrival';
      } else if (_lastPortController.text.trim().isNotEmpty || _ata != null) {
        movementType = 'arrival';
      } else if (_nextPortController.text.trim().isNotEmpty || _etd != null) {
        movementType = 'departure';
      }

      final logData = {
        'vesselName': _vesselNameController.text.trim(),
        'grossTonnage': _grossTonnageController.text.trim(),
        'netTonnage': _netTonnageController.text.trim(),
        'shippingCompany': _shippingCompanyController.text.trim(),
        'captainName': _captainNameController.text.trim(),
        'numberOfCrew': _numberOfCrewController.text.trim(),
        'lastPort': _lastPortController.text.trim(),
        'nextPort': _nextPortController.text.trim(),
        'numberOfPassengers': _numberOfPassengersController.text.trim(),
        'rollingCargo': _rollingCargoController.text.trim(),
        'cargoOnboard': _cargoOnboardController.text.trim(),
        'clearingOfficerName': _clearingOfficerNameController.text.trim(),
        'clearingOfficerContact': _clearingOfficerContactController.text.trim(),
        'movementType': movementType,
        'userId': userId,
        'userName': userName,
        'ata': _ata != null ? Timestamp.fromDate(_ata!) : null,
        'etd': _etd != null ? Timestamp.fromDate(_etd!) : null,
      };

      if (_editingLog != null) {
        // Update existing log
        await FirebaseFirestore.instance
            .collection('vesselArrivalDepartureLogs')
            .doc(_editingLog!['id'])
            .update(logData);
      } else {
        // Create new log
        logData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('vesselArrivalDepartureLogs')
            .add(logData);
      }

      setState(() {
        _formSuccess = true;
        _isSubmitting = false;
      });

      // Refresh logs
      await _fetchLogs();

      // Close modal after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showFormModal = false;
            _formSuccess = false;
            _editingLog = null;
          });
        }
      });
    } catch (error) {
      print('Error submitting log: $error');
      setState(() {
        _formError = _editingLog != null 
            ? 'Failed to update log. Please try again.' 
            : 'Failed to submit log. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return DateFormat('MM/dd/yyyy HH:mm').format(date);
  }

  // Determine actual movement type based on ETD
  String _getActualMovementType(Map<String, dynamic> log) {
    final originalType = log['movementType']?.toString() ?? 'departure';
    
    // If originally logged as departure, keep it as departure
    if (originalType == 'departure') {
      return 'departure';
    }
    
    // If originally logged as arrival, check if ETD has passed
    if (originalType == 'arrival') {
      final etd = log['etd'];
      if (etd != null) {
        DateTime? etdDate;
        if (etd is DateTime) {
          etdDate = etd;
        } else if (etd is Timestamp) {
          etdDate = etd.toDate();
        } else if (etd is String) {
          etdDate = DateTime.tryParse(etd);
        }
        
        if (etdDate != null) {
          final now = DateTime.now();
          // If ETD has passed, it's now a departure
          // Compare only date and time, not milliseconds
          if (etdDate.isBefore(now) || etdDate.isAtSameMomentAs(now)) {
            return 'departure';
          }
        }
      }
    }
    
    // Default to original type
    return originalType;
  }

  Future<void> _selectDate(BuildContext context, bool isAta) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isAta ? (_ata ?? DateTime.now()) : (_etd ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: isAta 
            ? (_ata != null ? TimeOfDay.fromDateTime(_ata!) : TimeOfDay.now())
            : (_etd != null ? TimeOfDay.fromDateTime(_etd!) : TimeOfDay.now()),
      );
      if (time != null) {
        final DateTime dateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        );
        setState(() {
          if (isAta) {
            _ata = dateTime;
          } else {
            _etd = dateTime;
          }
        });
      }
    }
  }

  Future<void> _selectFilterDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
      _filterLogs();
    }
  }

  void _viewLogDetails(Map<String, dynamic> log) {
    // Determine actual movement type based on ETD
    final actualMovementType = _getActualMovementType(log);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Log Details'),
            backgroundColor: const Color(0xFF0A4D68),
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vessel Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0A4D68), Color(0xFF088395)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              log['vesselName'] ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          // Movement Type Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: actualMovementType == 'departure' 
                                  ? const Color(0xFFFFF3CD) 
                                  : const Color(0xFFD4EDDA),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: actualMovementType == 'departure' 
                                    ? const Color(0xFFFFC107) 
                                    : const Color(0xFF28A745),
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  actualMovementType == 'departure' 
                                      ? Icons.sailing 
                                      : Icons.anchor,
                                  size: 14,
                                  color: actualMovementType == 'departure' 
                                      ? const Color(0xFF856404) 
                                      : const Color(0xFF155724),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  actualMovementType == 'departure' ? 'Departure' : 'Arrival',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: actualMovementType == 'departure' 
                                        ? const Color(0xFF856404) 
                                        : const Color(0xFF155724),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (log['grossTonnage'] != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${log['grossTonnage']} GT / ${log['netTonnage'] ?? 'N/A'} NT',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.access_time, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Submitted: ${_formatDate(log['createdAt'])}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Vessel Information Section
                _buildSectionHeader('Vessel Information'),
                const SizedBox(height: 12),
                _buildCompactDetailRow('Shipping Company', log['shippingCompany']),
                _buildCompactDetailRow('Captain', log['captainName']),
                _buildCompactDetailRow('Crew', log['numberOfCrew']?.toString()),
                _buildCompactDetailRow('Passengers', log['numberOfPassengers']),
                
                const SizedBox(height: 24),

                // Port Information Section
                _buildSectionHeader('Port Information'),
                const SizedBox(height: 12),
                // ATA Card (highlighted)
                if (log['ata'] != null || log['lastPort'] != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      border: Border.all(color: const Color(0xFF0D47A1), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.arrow_downward, color: Color(0xFF0D47A1), size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'ATA - Actual Time of Arrival',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D47A1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (log['lastPort'] != null)
                          _buildCompactInfoRow('Last Port', log['lastPort']),
                        if (log['ata'] != null)
                          _buildCompactInfoRow('Arrival Time', _formatDate(log['ata'])),
                      ],
                    ),
                  ),
                ],
                // ETD Card (highlighted)
                if (log['etd'] != null || log['nextPort'] != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      border: Border.all(color: const Color(0xFF856404), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.arrow_upward, color: Color(0xFF856404), size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'ETD - Estimated Time of Departure',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF856404),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (log['nextPort'] != null)
                          _buildCompactInfoRow('Next Port', log['nextPort']),
                        if (log['etd'] != null)
                          _buildCompactInfoRow('Departure Time', _formatDate(log['etd'])),
                      ],
                    ),
                  ),
                ],

                // Cargo Information Section
                if (log['rollingCargo'] != null || log['cargoOnboard'] != null) ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('Cargo Information'),
                  const SizedBox(height: 12),
                  if (log['rollingCargo'] != null)
                    _buildCompactDetailRow('Rolling Cargo', log['rollingCargo']),
                  if (log['cargoOnboard'] != null)
                    _buildCompactDetailRow('Cargo Onboard', log['cargoOnboard']),
                ],

                // Clearing Officer Section
                const SizedBox(height: 24),
                _buildSectionHeader('Clearing Officer'),
                const SizedBox(height: 12),
                _buildCompactDetailRow('Name', log['clearingOfficerName']),
                _buildCompactDetailRow('Contact', log['clearingOfficerContact']),
                
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF0A4D68),
      ),
    );
  }

  Widget _buildCompactDetailRow(String label, String? value) {
    if (value == null || value.toString().isEmpty || value == 'N/A') {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2C3E50),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color color,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 70),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Departure Logs (Admin)' : 'Departure Log'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                // Statistics Cards (Admin only)
                if (_isAdmin) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Total Logs',
                            value: _allLogs.length.toString(),
                            color: const Color(0xFF0A4D68),
                            borderColor: const Color(0xFF0A4D68),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Arrivals',
                            value: _allLogs.where((log) => _getActualMovementType(log) == 'arrival').length.toString(),
                            color: const Color(0xFF28A745),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Departures',
                            value: _allLogs.where((log) => _getActualMovementType(log) == 'departure').length.toString(),
                            color: const Color(0xFFFFC107),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Search and Filter Section
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by vessel name, company, ports...',
                          hintStyle: const TextStyle(fontSize: 14),
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (_) => _filterLogs(),
                      ),
                      // Type filter chips (for admin view)
                      if (_isAdmin) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilterChip(
                                label: const Text(
                                  'All',
                                  style: TextStyle(fontSize: 12),
                                ),
                                selected: _logTypeFilter == null,
                                onSelected: (selected) {
                                  setState(() {
                                    _logTypeFilter = null;
                                  });
                                  _filterLogs();
                                },
                                selectedColor: const Color(0xFF0A4D68).withOpacity(0.2),
                                checkmarkColor: const Color(0xFF0A4D68),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilterChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.anchor, size: 14),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Arrivals',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                selected: _logTypeFilter == 'arrival',
                                onSelected: (selected) {
                                  setState(() {
                                    _logTypeFilter = selected ? 'arrival' : null;
                                  });
                                  _filterLogs();
                                },
                                selectedColor: const Color(0xFF28A745).withOpacity(0.2),
                                checkmarkColor: const Color(0xFF28A745),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilterChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.sailing, size: 14),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Departures',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                selected: _logTypeFilter == 'departure',
                                onSelected: (selected) {
                                  setState(() {
                                    _logTypeFilter = selected ? 'departure' : null;
                                  });
                                  _filterLogs();
                                },
                                selectedColor: const Color(0xFFFFC107).withOpacity(0.2),
                                checkmarkColor: const Color(0xFFFFC107),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _selectFilterDate(context, true),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today, size: 16),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      _startDate == null
                                          ? 'Start Date'
                                          : DateFormat('MM/dd/yyyy').format(_startDate!),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('to', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _selectFilterDate(context, false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today, size: 16),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      _endDate == null
                                          ? 'End Date'
                                          : DateFormat('MM/dd/yyyy').format(_endDate!),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_startDate != null || _endDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _startDate = null;
                                  _endDate = null;
                                });
                                _filterLogs();
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Logs List
                Expanded(
                  child: _filteredLogs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.list_alt, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isNotEmpty || 
                                _startDate != null || 
                                _endDate != null ||
                                _logTypeFilter != null
                                    ? 'No logs match your search'
                                    : 'No logs found',
                                style: const TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchLogs,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredLogs.length,
                            itemBuilder: (context, index) {
                              final log = _filteredLogs[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  title: Text(
                                    log['vesselName'] ?? 'N/A',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 8),
                                      Text(
                                        'Company: ${log['shippingCompany'] ?? 'N/A'}',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      Text(
                                        'Captain: ${log['captainName'] ?? 'N/A'}',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      if (log['userName'] != null)
                                        Text(
                                          'Submitted by: ${log['userName']}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      Text(
                                        'Last Port: ${log['lastPort'] ?? 'N/A'}',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      Text(
                                        'Next Port: ${log['nextPort'] ?? 'N/A'}',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      if (log['ata'] != null)
                                        Text(
                                          'ATA: ${_formatDate(log['ata'])}',
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      if (log['etd'] != null)
                                        Text(
                                          'ETD: ${_formatDate(log['etd'])}',
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Date: ${_formatDate(log['createdAt'])}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.visibility),
                                        color: const Color(0xFF0A4D68),
                                        onPressed: () => _viewLogDetails(log),
                                      ),
                                      // Hide edit button for admins (view-only)
                                      if (!_isAdmin)
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          color: Colors.green,
                                          onPressed: () => _openEditForm(log),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          // Form Modal Overlay
          if (_showFormModal) _buildFormModal(),
        ],
      ),
      // Hide add button for admins (view-only)
      floatingActionButton: _isAdmin || _showFormModal
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAddForm,
              backgroundColor: const Color(0xFF0A4D68),
              icon: const Icon(Icons.add),
              label: const Text('Add New Log'),
            ),
    );
  }

  Widget _buildFormModal() {
    return Stack(
      children: [
        // Semi-transparent background
        ModalBarrier(
          color: Colors.black54,
          dismissible: !_isSubmitting,
          onDismiss: () {
            if (!_isSubmitting) {
              setState(() => _showFormModal = false);
            }
          },
        ),
        // Form Dialog
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0A4D68),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _editingLog != null
                            ? 'Edit Departure Log'
                            : 'Add Departure Log',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                setState(() => _showFormModal = false);
                              },
                      ),
                    ],
                  ),
                ),
                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_formError != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              border: Border.all(color: Colors.red),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_formError!)),
                              ],
                            ),
                          ),
                        if (_formSuccess)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              border: Border.all(color: Colors.green),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Log submitted successfully!'),
                              ],
                            ),
                          ),
                        // Form Fields
                        TextField(
                          controller: _vesselNameController,
                          decoration: const InputDecoration(
                            labelText: 'Vessel Name *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _grossTonnageController,
                                decoration: const InputDecoration(
                                  labelText: 'Gross Tonnage (GT)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _netTonnageController,
                                decoration: const InputDecoration(
                                  labelText: 'Net Tonnage (NT)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          value: _selectedShippingCompany != null && 
                                 _shippingCompanyList.contains(_selectedShippingCompany)
                            ? _selectedShippingCompany
                            : null,
                          decoration: const InputDecoration(
                            labelText: 'Shipping Company *',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'Select shipping company',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ..._shippingCompanyList.map((company) {
                              return DropdownMenuItem<String?>(
                                value: company,
                                child: Text(
                                  company,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              );
                            }),
                          ],
                          isExpanded: true,
                          selectedItemBuilder: (BuildContext context) {
                            return [
                              const Text(
                                'Select shipping company',
                                overflow: TextOverflow.ellipsis,
                              ),
                              ..._shippingCompanyList.map((company) {
                                return Text(
                                  company,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                );
                              }),
                            ];
                          },
                          onChanged: (value) {
                            setState(() {
                              _selectedShippingCompany = value;
                              _shippingCompanyController.text = value ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _captainNameController,
                          decoration: const InputDecoration(
                            labelText: 'Captain\'s Name *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _numberOfCrewController,
                          decoration: const InputDecoration(
                            labelText: 'Number of Crew',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _lastPortController,
                                decoration: const InputDecoration(
                                  labelText: 'Last Port',
                                  border: OutlineInputBorder(),
                                  hintText: 'For Arrival',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _nextPortController,
                                decoration: const InputDecoration(
                                  labelText: 'Next Port',
                                  border: OutlineInputBorder(),
                                  hintText: 'For Departure',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.access_time),
                                label: Text(_ata == null
                                    ? 'ATA (Actual Time of Arrival) *'
                                    : _formatDate(_ata!)),
                                onPressed: () => _selectDate(context, true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.access_time),
                                label: Text(_etd == null
                                    ? 'ETD (Estimated Time of Departure)'
                                    : _formatDate(_etd!)),
                                onPressed: () => _selectDate(context, false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _numberOfPassengersController,
                          decoration: const InputDecoration(
                            labelText: 'Number of Passengers Onboard *',
                            border: OutlineInputBorder(),
                            hintText: 'Enter number or "Nil" if cargo-only',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _rollingCargoController,
                          decoration: const InputDecoration(
                            labelText: 'Rolling Cargo Onboard',
                            border: OutlineInputBorder(),
                            hintText: 'e.g., 5 trucks, 2 cars',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _cargoOnboardController,
                          decoration: const InputDecoration(
                            labelText: 'Cargo Onboard',
                            border: OutlineInputBorder(),
                            hintText: 'e.g., 64,000 sacks of cement',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _clearingOfficerNameController,
                          decoration: const InputDecoration(
                            labelText: 'Clearing Officer Name *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _clearingOfficerContactController,
                          decoration: const InputDecoration(
                            labelText: 'Clearing Officer Contact Number *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),
                ),
                // Footer Actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                setState(() => _showFormModal = false);
                              },
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A4D68),
                          foregroundColor: Colors.white,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(_editingLog != null ? 'Update Log' : 'Submit Log'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

