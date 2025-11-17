import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';

class RequestVesselAccessScreen extends StatefulWidget {
  const RequestVesselAccessScreen({super.key});

  @override
  State<RequestVesselAccessScreen> createState() => _RequestVesselAccessScreenState();
}

class _RequestVesselAccessScreenState extends State<RequestVesselAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vesselNameController = TextEditingController();
  final _additionalInfoController = TextEditingController();
  
  String _selectedPosition = '';
  String _selectedRequestType = 'crew_access';
  bool _isLoading = false;
  bool _isSearching = false;
  List<QueryDocumentSnapshot> _vesselSearchResults = [];
  QueryDocumentSnapshot? _selectedVessel;
  bool _showRequestForm = false;

  final List<String> _vesselPositions = [
    'Master',
    'Chief Officer',
    'Chief Engineer',
    '2nd Officer',
    '3rd Officer',
    'Engineer',
    'Deck Rating',
    'Engine Rating',
    'Cook',
    'Steward',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _vesselNameController.addListener(_onVesselNameChanged);
    _additionalInfoController.addListener(_onAdditionalInfoChanged);
  }

  @override
  void dispose() {
    _vesselNameController.removeListener(_onVesselNameChanged);
    _additionalInfoController.removeListener(_onAdditionalInfoChanged);
    _vesselNameController.dispose();
    _additionalInfoController.dispose();
    super.dispose();
  }

  void _onAdditionalInfoChanged() {
    // Trigger validation when additional info changes
    if (_formKey.currentState != null) {
      _formKey.currentState!.validate();
    }
  }

  void _onVesselNameChanged() {
    final query = _vesselNameController.text.trim();
    if (query.length >= 3) {
      _searchVessels(query);
    } else {
      setState(() {
        _vesselSearchResults = [];
        _selectedVessel = null;
      });
    }
  }

  Future<void> _searchVessels(String vesselName) async {
    setState(() => _isSearching = true);
    
    try {
      final searchLower = vesselName.toLowerCase().trim();
      
      if (searchLower.isEmpty) {
        setState(() {
          _vesselSearchResults = [];
          _selectedVessel = null;
          _isSearching = false;
        });
        return;
      }
      
      // Fetch all vessels and filter in memory for case-insensitive partial matching
      // Using pagination to get all vessels if needed
      List<QueryDocumentSnapshot> allVessels = [];
      QuerySnapshot? snapshot;
      QueryDocumentSnapshot? lastDoc;
      
      do {
        Query query = FirebaseFirestore.instance.collection('vessels');
        
        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }
        
        snapshot = await query.limit(100).get();
        allVessels.addAll(snapshot.docs);
        
        if (snapshot.docs.isNotEmpty) {
          lastDoc = snapshot.docs.last;
        }
      } while (snapshot.docs.length == 100 && allVessels.length < 500); // Limit to 500 to avoid performance issues
      
      // Filter vessels where name contains the search term (case-insensitive)
      final filteredDocs = allVessels.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final vesselNameValue = (data['vesselName'] ?? '').toString().toLowerCase().trim();
        return vesselNameValue.contains(searchLower);
      }).toList();
      
      setState(() {
        _vesselSearchResults = filteredDocs;
        
        // Auto-select if there's exactly one match
        if (filteredDocs.length == 1) {
          _selectedVessel = filteredDocs.first;
        } else if (filteredDocs.isNotEmpty) {
          // Check for exact match (case-insensitive)
          final exactMatch = filteredDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final vesselNameValue = (data['vesselName'] ?? '').toString().toLowerCase().trim();
            return vesselNameValue == searchLower;
          }).toList();
          
          if (exactMatch.isNotEmpty) {
            // Found exact match - auto-select it
            _selectedVessel = exactMatch.first;
          } else {
            // No exact match, don't auto-select - user must click
            // But keep previous selection if it still matches
            if (_selectedVessel != null) {
              final isStillValid = filteredDocs.any(
                (doc) => doc.id == _selectedVessel!.id,
              );
              if (!isStillValid) {
                _selectedVessel = null;
              }
            } else {
              _selectedVessel = null;
            }
          }
        } else {
          _selectedVessel = null;
        }
        
        // Trigger validation update if vessel was auto-selected
        if (_selectedVessel != null && _formKey.currentState != null) {
          _formKey.currentState!.validate();
        }
      });
    } catch (e) {
      print('Error searching vessels: $e');
      setState(() {
        _vesselSearchResults = [];
        _selectedVessel = null;
      });
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Stream<QuerySnapshot> _getUserRequestsStream() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['uid'];
    
    if (userId == null) {
      // Return empty stream if user not authenticated
      return const Stream<QuerySnapshot>.empty();
    }
    
    // Query with requesterId
    // Note: We sort by createdAt in memory to avoid Firestore index requirements
    return FirebaseFirestore.instance
        .collection('vesselAccessRequests')
        .where('requesterId', isEqualTo: userId)
        .snapshots();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedVessel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a vessel from the search results'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?['uid'];
      final userEmail = authProvider.user?['email'] ?? '';
      final userName = authProvider.user?['username'] ?? userEmail;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final vesselData = _selectedVessel!.data() as Map<String, dynamic>;
      
      // Check for existing pending request
      final existingRequest = await FirebaseFirestore.instance
          .collection('vesselAccessRequests')
          .where('requesterId', isEqualTo: userId)
          .where('vesselId', isEqualTo: _selectedVessel!.id)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingRequest.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have a pending request for this vessel'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Create request document
      final requestData = {
        'vesselId': _selectedVessel!.id,
        'vesselName': vesselData['vesselName'] ?? _vesselNameController.text.trim(),
        'requesterId': userId,
        'userId': userId, // Store both for web app compatibility
        'requesterEmail': userEmail,
        'requesterName': userName,
        'position': _selectedPosition,
        'requestType': _selectedRequestType,
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
        'reviewedBy': null,
        'reviewedAt': null,
        'reviewComments': null,
        'additionalInfo': _additionalInfoController.text.trim(),
        'accessLevel': 'crew',
        'createdAt': DateTime.now().toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await FirebaseFirestore.instance
          .collection('vesselAccessRequests')
          .add(requestData);

      // Create notifications for admins
      _createAdminNotifications(requestData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access request submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Reset form
        _vesselNameController.clear();
        _additionalInfoController.clear();
        _selectedPosition = '';
        _selectedVessel = null;
        _vesselSearchResults = [];
        _showRequestForm = false;
        
      // Requests will auto-update via StreamBuilder
      }
    } catch (error) {
      print('Error submitting request: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createAdminNotifications(Map<String, dynamic> requestData) async {
    try {
      final adminsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (var adminDoc in adminsSnapshot.docs) {
        final adminId = adminDoc.id;
        final notificationRef = FirebaseFirestore.instance
            .collection('notifications')
            .doc();
        
        batch.set(notificationRef, {
          'userId': adminId,
          'type': 'vessel_access_request',
          'title': 'New Vessel Access Request',
          'message': '${requestData['requesterName']} has requested access to vessel "${requestData['vesselName']}"',
          'vesselId': requestData['vesselId'],
          'vesselName': requestData['vesselName'],
          'requestId': notificationRef.id,
          'requesterName': requestData['requesterName'],
          'requesterId': requestData['requesterId'],
          'position': requestData['position'],
          'timestamp': DateTime.now().toIso8601String(),
          'isRead': false,
          'priority': 'normal',
          'redirectUrl': '/admin/vessel-access',
          'isSystemNotification': true,
          'notificationType': 'access_request',
        });
      }

      await batch.commit();
    } catch (e) {
      print('Error creating admin notifications: $e');
      // Don't fail the request if notifications fail
    }
  }

  Future<void> _deleteRequest(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Request'),
        content: const Text('Are you sure you want to delete this request? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('vesselAccessRequests')
          .doc(requestId)
          .delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Requests will auto-update via StreamBuilder
      }
    } catch (e) {
      print('Error deleting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Vessel Access'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Card(
              color: const Color(0xFF0A4D68),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔑 Request Vessel Access',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Request access to existing vessels for crew operations, crew changes, or temporary access.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Request Form Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A4D68).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.handshake,
                            color: Color(0xFF0A4D68),
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Request Access to Existing Vessel',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0A4D68),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Need access to a vessel that\'s already registered? Submit a request for admin approval.',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _showRequestForm = !_showRequestForm);
                      },
                      icon: Icon(_showRequestForm ? Icons.close : Icons.add),
                      label: Text(_showRequestForm ? 'Close Form' : 'Submit Access Request'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A4D68),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            if (_showRequestForm) ...[
              const SizedBox(height: 16),
              _buildRequestForm(),
            ],
            
            const SizedBox(height: 32),
            
            // User Requests Section
            const Text(
              '📋 My Access Requests',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A4D68),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Track the status of your vessel access requests',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            
            // Requests List with StreamBuilder for real-time updates
            StreamBuilder<QuerySnapshot>(
              stream: _getUserRequestsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red, size: 48),
                          const SizedBox(height: 8),
                          Text(
                            'Error loading requests: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                
                final requests = snapshot.data?.docs ?? [];
                
                if (requests.isEmpty) {
                  return _buildEmptyState();
                }
                
                // Sort by createdAt if available (descending)
                final sortedRequests = List<QueryDocumentSnapshot>.from(requests);
                sortedRequests.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aCreated = aData['createdAt'] ?? aData['requestedAt'] ?? '';
                  final bCreated = bData['createdAt'] ?? bData['requestedAt'] ?? '';
                  try {
                    final aDate = DateTime.parse(aCreated.toString());
                    final bDate = DateTime.parse(bCreated.toString());
                    return bDate.compareTo(aDate); // Descending
                  } catch (e) {
                    return 0;
                  }
                });
                
                return Column(
                  children: sortedRequests.map((requestDoc) {
                    final request = requestDoc.data() as Map<String, dynamic>;
                    return _buildRequestCard(requestDoc.id, request);
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestForm() {
    return Card(
      elevation: 2,
      child: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request Vessel Access',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A4D68),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Request access to an existing vessel if you are a crew member',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              
              // Vessel Name Search
              TextFormField(
                controller: _vesselNameController,
                decoration: InputDecoration(
                  labelText: 'Vessel Name *',
                  hintText: 'Type vessel name to search...',
                  prefixIcon: const Icon(Icons.sailing),
                  suffixIcon: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_selectedVessel != null
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _selectedVessel != null ? Colors.green : Colors.grey,
                      width: _selectedVessel != null ? 2 : 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _selectedVessel != null ? Colors.green : Colors.grey,
                      width: _selectedVessel != null ? 2 : 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _selectedVessel != null ? Colors.green : const Color(0xFF0A4D68),
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vessel name is required';
                  }
                  if (_selectedVessel == null) {
                    return 'Please select a vessel from the search results below';
                  }
                  return null;
                },
              ),
              
              // Vessel Search Results
              if (_vesselSearchResults.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedVessel != null ? Colors.green : Colors.grey[300]!,
                      width: _selectedVessel != null ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _vesselSearchResults.length,
                    itemBuilder: (context, index) {
                      final vessel = _vesselSearchResults[index];
                      final data = vessel.data() as Map<String, dynamic>;
                      final isSelected = _selectedVessel?.id == vessel.id;
                      
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedVessel = vessel;
                          });
                          // Trigger form validation update
                          _formKey.currentState?.validate();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Colors.green[50]
                                : null,
                            border: Border(
                              bottom: index < _vesselSearchResults.length - 1
                                  ? BorderSide(color: Colors.grey[200]!)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            data['vesselName'] ?? 'Unknown',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isSelected 
                                                  ? Colors.green[700]
                                                  : Colors.black87,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isSelected) ...[
                                          const SizedBox(width: 8),
                                          Icon(Icons.check_circle, 
                                            color: Colors.green, 
                                            size: 20,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Type: ${data['vesselType'] ?? 'N/A'} | IMO: ${data['imoNumber'] ?? 'N/A'}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Company: ${data['companyOwner'] ?? 'N/A'}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (data['submissionStatus'] != null) ...[
                                      const SizedBox(height: 4),
                                      _buildStatusChip(data['submissionStatus']),
                                    ],
                                  ],
                                ),
                              ),
                              if (!isSelected) ...[
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedVessel = vessel;
                                    });
                                    _formKey.currentState?.validate();
                                  },
                                  child: const Text('Select'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ] else if (_vesselNameController.text.trim().length >= 3 && !_isSearching) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No vessels found matching "${_vesselNameController.text.trim()}". Please check the spelling or try a different search term.',
                          style: TextStyle(color: Colors.orange[900], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Position Dropdown
              DropdownButtonFormField<String>(
                value: _selectedPosition.isEmpty ? null : _selectedPosition,
                decoration: InputDecoration(
                  labelText: 'Your Position *',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _vesselPositions.map((position) {
                  return DropdownMenuItem(
                    value: position,
                    child: Text(position),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedPosition = value ?? '');
                  // Trigger validation when position changes
                  _formKey.currentState?.validate();
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Position is required';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // Request Type
              DropdownButtonFormField<String>(
                value: _selectedRequestType,
                decoration: InputDecoration(
                  labelText: 'Request Type',
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'crew_access', child: Text('Crew Access')),
                  DropdownMenuItem(value: 'crew_change', child: Text('Crew Change')),
                  DropdownMenuItem(value: 'temporary_access', child: Text('Temporary Access')),
                ],
                onChanged: (value) {
                  setState(() => _selectedRequestType = value ?? 'crew_access');
                },
              ),
              
              const SizedBox(height: 16),
              
              // Additional Info
              TextFormField(
                controller: _additionalInfoController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Additional Information *',
                  hintText: 'Please explain why you need access to this vessel, your role, and any other relevant information...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Additional information is required';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // Selected Vessel Summary
              if (_selectedVessel != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0A4D68)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected Vessel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A4D68),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildVesselSummary(_selectedVessel!),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A4D68),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send),
                            SizedBox(width: 8),
                            Text('Submit Request'),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVesselSummary(QueryDocumentSnapshot vessel) {
    final data = vessel.data() as Map<String, dynamic>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryRow('Name', data['vesselName'] ?? 'N/A'),
        _buildSummaryRow('Type', data['vesselType'] ?? 'N/A'),
        _buildSummaryRow('Company', data['companyOwner'] ?? 'N/A'),
        _buildSummaryRow('Status', data['submissionStatus'] ?? 'Pending'),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Access Requests Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You haven\'t submitted any vessel access requests. Click the button above to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildRequestCard(String requestId, Map<String, dynamic> request) {
    final status = request['status'] ?? 'pending';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['vesselName'] ?? 'Unknown Vessel',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A4D68),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getRequestTypeDisplay(request['requestType'] ?? ''),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _getStatusBadge(status),
              ],
            ),
            
            const Divider(height: 24),
            
            // Details
            _buildDetailRow('Your Position', request['position'] ?? 'N/A'),
            _buildDetailRow(
              'Submitted',
              _formatDate(request['createdAt']),
            ),
            if (request['updatedAt'] != request['createdAt'])
              _buildDetailRow(
                'Last Updated',
                _formatDate(request['updatedAt']),
              ),
            if (request['additionalInfo'] != null && request['additionalInfo'].toString().isNotEmpty)
              _buildDetailRow('Message', request['additionalInfo']),
            if (request['reviewComments'] != null && request['reviewComments'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin Comments:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(request['reviewComments']),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Actions
            Row(
              children: [
                if (status == 'pending') ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteRequest(requestId),
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
                if (status == 'approved') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // View details
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Access Granted'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                ],
                if (status == 'rejected') ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // View reason
                      },
                      icon: const Icon(Icons.info),
                      label: const Text('View Reason'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color backgroundColor;
    IconData icon;
    String text;

    switch (status.toLowerCase()) {
      case 'approved':
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
        text = 'APPROVED';
        break;
      case 'pending':
        backgroundColor = Colors.orange;
        icon = Icons.access_time;
        text = 'PENDING';
        break;
      case 'declined':
        backgroundColor = Colors.red;
        icon = Icons.cancel;
        text = 'DECLINED';
        break;
      default:
        backgroundColor = Colors.grey;
        icon = Icons.help_outline;
        text = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: backgroundColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: backgroundColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: backgroundColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _getStatusBadge(String status) {
    Color backgroundColor;
    IconData icon;
    String text;

    switch (status.toLowerCase()) {
      case 'pending':
        backgroundColor = Colors.orange;
        icon = Icons.access_time;
        text = 'PENDING';
        break;
      case 'approved':
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
        text = 'APPROVED';
        break;
      case 'rejected':
        backgroundColor = Colors.red;
        icon = Icons.cancel;
        text = 'REJECTED';
        break;
      default:
        backgroundColor = Colors.grey;
        icon = Icons.help_outline;
        text = 'UNKNOWN';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _getRequestTypeDisplay(String requestType) {
    switch (requestType) {
      case 'crew_access':
        return 'Crew Access';
      case 'crew_change':
        return 'Crew Change';
      case 'temporary_access':
        return 'Temporary Access';
      default:
        return requestType;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      if (date is String) {
        final parsed = DateTime.parse(date);
        return '${parsed.day}/${parsed.month}/${parsed.year}';
      } else if (date is Timestamp) {
        final parsed = date.toDate();
        return '${parsed.day}/${parsed.month}/${parsed.year}';
      }
      return date.toString();
    } catch (e) {
      return date.toString();
    }
  }
}

