import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'add_vessel_screen_v2.dart';
import 'document_renewal_dialog.dart';
import 'add_crew_member_dialog.dart';
import '../models/document_item.dart';

class VesselDetailScreen extends StatefulWidget {
  final String vesselId;
  final Map<String, dynamic> vesselData;

  const VesselDetailScreen({
    super.key,
    required this.vesselId,
    required this.vesselData,
  });

  @override
  State<VesselDetailScreen> createState() => _VesselDetailScreenState();
}

class _VesselDetailScreenState extends State<VesselDetailScreen> {
  int _selectedStepIndex = 0; // Track which step is selected
  int _certTabIndex = 0;
  int _crewTabIndex = 0;
  Map<String, dynamic>? _vesselData; // Local state for vessel data

  @override
  void initState() {
    super.initState();
    _vesselData = widget.vesselData;
    _loadVesselData(); // Load initial data and listen for updates
  }

  Future<void> _loadVesselData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('vessels')
          .doc(widget.vesselId)
          .get();
      
      if (doc.exists && mounted) {
        setState(() {
          _vesselData = doc.data();
        });
      }
    } catch (e) {
      debugPrint('Error loading vessel data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use local state if available, otherwise fallback to widget data
    final currentVesselData = _vesselData ?? widget.vesselData;
    return Scaffold(
      appBar: AppBar(
        title: Text((_vesselData?['vesselName'] ?? widget.vesselData['vesselName'] ?? 'Vessel Details').toString()),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Vessel',
            onPressed: () {
              // Navigate immediately - loading will be shown in the edit screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddVesselScreenV2(
                    vesselId: widget.vesselId,
                    vesselData: widget.vesselData,
                  ),
                ),
              );
              },
          ),
        ],
      ),
      body: Column(
        children: [
          // Step Navigation
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _buildStepButton(0, 'Step 1', 'Vessel Info', Icons.info),
                  _buildStepButton(1, 'Step 2', 'General Particulars', Icons.description),
                  _buildStepButton(2, 'Step 3', 'Manning', Icons.people_outline),
                  _buildStepButton(3, 'Step 4', 'Certificates', Icons.verified, highlight: true),
                  _buildStepButton(4, 'Step 5', 'Officers & Crew', Icons.person, highlight: true),
                ],
              ),
            ),
          ),
          
          // Step Content
          Expanded(
            child: IndexedStack(
              index: _selectedStepIndex,
              children: [
                _buildStep1Tab(),
                _buildStep2Tab(),
                _buildStep3Tab(),
                _buildStep4Tab(),
                _buildStep5Tab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepButton(int index, String stepNum, String label, IconData icon, {bool highlight = false}) {
    final isSelected = _selectedStepIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () => setState(() => _selectedStepIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? (highlight ? Colors.orange : const Color(0xFF0A4D68))
                : (highlight ? Colors.orange.withOpacity(0.1) : Colors.white),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected 
                  ? (highlight ? Colors.orange : const Color(0xFF0A4D68))
                  : (highlight ? Colors.orange : Colors.grey[300]!),
              width: highlight ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected 
                    ? Colors.white 
                    : (highlight ? Colors.orange : Colors.grey[700]),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stepNum,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected 
                          ? Colors.white 
                          : (highlight ? Colors.orange : Colors.grey[700]),
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected 
                          ? Colors.white 
                          : (highlight ? Colors.orange : Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1Tab() {
    // Step 1: Vessel Information
    final data = _vesselData ?? widget.vesselData;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vessel Summary Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          color: const Color(0xFF0A4D68).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.sailing, size: 32, color: Color(0xFF0A4D68)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['vesselName'] ?? 'Unknown Vessel',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0A4D68),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['vesselType'] ?? 'N/A',
                              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          _buildSectionTitle('Vessel Information'),
          _buildInfoCard([
            _buildInfoRow('Vessel Name', data['vesselName'] ?? 'N/A'),
            _buildInfoRow('Vessel Type', data['vesselType'] ?? 'N/A'),
            _buildInfoRow('IMO Number', data['imoNumber'] ?? 'N/A'),
            _buildInfoRow('Company Owner', data['companyOwner'] ?? 'N/A'),
            _buildInfoRow('Shipping Code', data['shippingCode'] ?? 'N/A'),
            _buildInfoRow('Gross Tonnage', data['grossTonnage'] ?? 'N/A'),
            _buildInfoRow('Net Tonnage', data['netTonnage'] ?? 'N/A'),
            _buildInfoRow('Year Built', data['yearBuilt'] ?? 'N/A'),
            _buildInfoRow('Place Built', data['placeBuilt'] ?? 'N/A'),
            _buildInfoRow('Homeport', data['homeport'] ?? 'N/A'),
            _buildInfoRow('Hull Material', data['hullMaterial'] ?? 'N/A'),
            _buildInfoRow('Length', data['length'] ?? 'N/A'),
            _buildInfoRow('Number of Engines', data['numberOfEngine'] ?? 'N/A'),
            _buildInfoRow('Power (kW)', data['kilowatt'] ?? 'N/A'),
          ]),
          
          const SizedBox(height: 24),
          _buildSectionTitle('Master & Chief Engineer'),
          _buildInfoCard([
            _buildInfoRow('Master', data['master'] ?? 'N/A'),
            _buildInfoRow('Chief Engineer', data['chiefEngineer'] ?? 'N/A'),
            _buildInfoRow('Contact Number', data['contactNumber'] ?? 'N/A'),
          ]),
        ],
      ),
    );
  }
  
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Tab() {
    // Step 2: General Particulars
    final data = _vesselData ?? widget.vesselData;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHighlightedSection('Step 2: General Particulars'),
          const SizedBox(height: 16),
          _buildInfoCard([
            _buildInfoRow('Type of Ship', data['typeOfShip'] ?? 'N/A'),
            _buildInfoRow('Gross Tonnage', data['grossTonnage'] ?? 'N/A'),
            _buildInfoRow('Net Tonnage', data['netTonnage'] ?? 'N/A'),
            _buildInfoRow('Place Built', data['placeBuilt'] ?? 'N/A'),
            _buildInfoRow('Year Built', data['yearBuilt'] ?? 'N/A'),
            _buildInfoRow('Builder', data['builder'] ?? 'N/A'),
            _buildInfoRow('Length', data['length'] ?? 'N/A'),
            _buildInfoRow('Homeport', data['homeport'] ?? 'N/A'),
            _buildInfoRow('Hull Material', data['hullMaterial'] ?? 'N/A'),
            _buildInfoRow('Number of Engines', data['numberOfEngine'] ?? 'N/A'),
            _buildInfoRow('Power (kW)', data['kilowatt'] ?? 'N/A'),
          ]),
        ],
      ),
    );
  }

  // Helper function to extract manning data from lists by position
  Map<String, String> _getManningDataByPosition(
    List<dynamic>? departmentList,
    String position,
  ) {
    if (departmentList == null || departmentList.isEmpty) {
      return {'license': 'N/A', 'number': 'N/A'};
    }

    for (var entry in departmentList) {
      final entryMap = entry as Map<String, dynamic>?;
      if (entryMap == null) continue;
      
      final entryPosition = entryMap['position']?.toString().toUpperCase().trim() ?? '';
      if (entryPosition == position.toUpperCase().trim()) {
        return {
          'license': entryMap['license']?.toString() ?? 'N/A',
          'number': entryMap['number']?.toString() ?? 'N/A',
        };
      }
    }

    return {'license': 'N/A', 'number': 'N/A'};
  }

  Widget _buildStep3Tab() {
    // Step 3: Manning Requirements
    final data = _vesselData ?? widget.vesselData;
    
    // Get deck and engine department lists
    final deckDepartment = data['deckDepartment'] as List? ?? [];
    final engineDepartment = data['engineDepartment'] as List? ?? [];
    
    // Extract data for each position from the lists
    final masterData = _getManningDataByPosition(deckDepartment, 'MASTER');
    final chiefOfficerData = _getManningDataByPosition(deckDepartment, 'CHIEF OFFICER');
    final deckRatingsData = _getManningDataByPosition(deckDepartment, 'RATINGS');
    
    final chiefEngineOfficerData = _getManningDataByPosition(engineDepartment, 'CHIEF ENGINE OFFICER');
    final engineOfficerData = _getManningDataByPosition(engineDepartment, 'ENGINE OFFICER');
    final engineRatingsData = _getManningDataByPosition(engineDepartment, 'RATINGS');
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHighlightedSection('Step 3: Manning Requirements'),
          const SizedBox(height: 16),
          
          // Deck Department
          _buildSectionTitle('Deck Department'),
          _buildManningTable([
            ['MASTER', masterData['license'] ?? 'N/A', masterData['number'] ?? 'N/A'],
            ['CHIEF OFFICER', chiefOfficerData['license'] ?? 'N/A', chiefOfficerData['number'] ?? 'N/A'],
            ['RATINGS', deckRatingsData['license'] ?? 'N.A', deckRatingsData['number'] ?? 'N/A'],
          ]),
          
          const SizedBox(height: 24),
          
          // Engine Department
          _buildSectionTitle('Engine Department'),
          _buildManningTable([
            ['CHIEF ENGINE OFFICER', chiefEngineOfficerData['license'] ?? 'N/A', chiefEngineOfficerData['number'] ?? 'N/A'],
            ['ENGINE OFFICER', engineOfficerData['license'] ?? 'N/A', engineOfficerData['number'] ?? 'N/A'],
            ['RATINGS', engineRatingsData['license'] ?? 'N.A', engineRatingsData['number'] ?? 'N/A'],
          ]),
          
          const SizedBox(height: 24),
          
          // PSSC
          _buildSectionTitle('Total Number of Persons Allowed Onboard (PSSC)'),
          _buildPsscCard(
            authorizedCrew: data['authorizedCrew']?.toString() ?? 'N/A',
            othersNumber: data['othersNumber']?.toString() ?? 'N/A',
            passengerAccommodation: data['passengerAccommodation']?.toString() ?? 'N.A',
          ),
        ],
      ),
    );
  }

  Widget _buildStep4Tab() {
    // Step 4: Certificates (HIGHLIGHTED) - Filter by No Expiry and Expiry Certificates
    final data = _vesselData ?? widget.vesselData;
    final expiryCertificates = data['expiryCertificates'] as List? ?? [];
    final noExpiryDocs = data['noExpiryDocs'] as List? ?? [];

    return Column(
      children: [
        // Highlighted Header for Step 4
        Container(
          color: Colors.orange.withOpacity(0.1),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.verified, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step 4: Certificates & Shipping Company',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[900],
                      ),
                    ),
                    Text(
                      'Review all vessel certificates carefully',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          color: Colors.grey[200],
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _certTabIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _certTabIndex == 0 ? Colors.blue : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: _certTabIndex == 0 ? Colors.blue : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'No Expiry (3)',
                        style: TextStyle(
                          color: _certTabIndex == 0 ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _certTabIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _certTabIndex == 1 ? Colors.purple : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: _certTabIndex == 1 ? Colors.purple : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Expiry Certificates (${expiryCertificates.length})',
                        style: TextStyle(
                          color: _certTabIndex == 1 ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _certTabIndex,
            children: [
              _buildNoExpiryCertificateList(noExpiryDocs),
              _buildExpiryCertificateList(expiryCertificates),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoExpiryCertificateList(List<dynamic> certificates) {
    // Always show the three no-expiry certificate types (matching web app behavior)
    final List<String> noExpiryCertificateTypes = [
      'CERTIFICATE OF PHILIPPINE REGISTRY',
      'CERTIFICATE OF OWNERSHIP',
      'TONNAGE MEASUREMENT',
    ];

    // Create a map from certificate type to certificate data for quick lookup
    final Map<String, Map<String, dynamic>> certMap = {};
    for (var cert in certificates) {
      final certType = cert['certificateType']?.toString() ?? '';
      if (certType.isNotEmpty) {
        certMap[certType] = cert as Map<String, dynamic>;
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: noExpiryCertificateTypes.length,
      itemBuilder: (context, index) {
        final certType = noExpiryCertificateTypes[index];
        final cert = certMap[certType];
        
        // Get date issued from certificate or empty string
        final dateIssued = cert?['dateIssued']?.toString() ?? '';
        
        // Determine remarks/status - if date is present, it's VALID
        final remarks = dateIssued.isNotEmpty 
            ? (cert?['status'] ?? cert?['remarks'] ?? 'VALID')
            : 'N/A';
        
        // Get file URL
        final fileUrl = cert?['url'] ?? 
                        cert?['certificateFileUrl'] ?? 
                        cert?['fileUrl'] ?? 
                        cert?['downloadURL'] ?? 
                        cert?['cloudinaryUrl'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        certType,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'No Expiry',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (dateIssued.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Date Issued: $dateIssued',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Remarks: ',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (remarks == 'VALID' || remarks == 'Valid') 
                            ? Colors.green.withOpacity(0.2) 
                            : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        remarks,
                        style: TextStyle(
                          fontSize: 11,
                          color: (remarks == 'VALID' || remarks == 'Valid') 
                              ? Colors.green[700] 
                              : Colors.grey[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (fileUrl != null && fileUrl.toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.attach_file, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                              onTap: () {
                            _viewFile(fileUrl.toString());
                            },
                          child: Text(
                            'View Certificate File',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Update/Upload Button
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _updateCertificate(
                          cert ?? {},
                          'noExpiry',
                          certificateType: certType,
                        ),
                        icon: const Icon(Icons.update, size: 18),
                        label: const Text('Update'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A4D68),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpiryCertificateList(List<dynamic> certificates) {
    if (certificates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No certificates found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: certificates.length,
      itemBuilder: (context, index) {
        final cert = certificates[index] as Map<String, dynamic>;
        Color statusColor;
        String statusText;
        
        if (cert['dateExpiry'] != null && cert['dateExpiry'].toString().isNotEmpty) {
          try {
            DateTime expiryDate;
            final dateStr = cert['dateExpiry'].toString();
            
            if (dateStr.contains('/')) {
              final parts = dateStr.split('/');
              if (parts.length == 3) {
                expiryDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
              } else {
                expiryDate = DateTime.parse(dateStr);
              }
            } else {
              expiryDate = DateTime.parse(dateStr);
            }
            
            if (expiryDate.isBefore(now)) {
              statusColor = Colors.red;
              statusText = 'Expired';
            } else if (expiryDate.isBefore(thirtyDaysFromNow)) {
              statusColor = Colors.orange;
              statusText = 'Expiring Soon';
            } else {
              statusColor = Colors.green;
              statusText = 'Valid';
            }
          } catch (e) {
            statusColor = Colors.green;
            statusText = 'Valid';
          }
        } else {
          statusColor = Colors.green;
          statusText = 'Valid';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cert['certificateType'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (cert['dateExpiry'] != null && cert['dateExpiry'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Expires: ${cert['dateExpiry']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                if (cert['dateIssued'] != null && cert['dateIssued'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Issued: ${cert['dateIssued']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                // Show remarks/status if available
                if (cert['status'] != null || cert['remarks'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Remarks: ',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (cert['status'] == 'VALID' || cert['remarks'] == 'VALID') ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          cert['status'] ?? cert['remarks'] ?? 'N/A',
                          style: TextStyle(
                            fontSize: 11,
                            color: (cert['status'] == 'VALID' || cert['remarks'] == 'VALID') ? Colors.green[700] : Colors.red[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (cert['certificateFileUrl'] != null || cert['fileUrl'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.attach_file, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                              onTap: () {
                            // Open file viewer
                            _viewFile(cert['certificateFileUrl'] ?? cert['fileUrl']);
                            },
                          child: Text(
                            'View Certificate File',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Update/Renew Button
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _updateCertificate(cert, 'expiry'),
                        icon: const Icon(Icons.update, size: 18),
                        label: Text(
                          statusText == 'Expired' ? 'Renew' : 'Update',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: statusText == 'Expired' ? Colors.red : const Color(0xFF0A4D68),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _viewFile(String? fileUrl) async {
    if (fileUrl == null || fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file available')),
      );
      return;
    }
    
    try {
      final Uri url = Uri.parse(fileUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open the document. URL: $url'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening document: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
  
  Future<void> _updateCertificate(Map<String, dynamic> cert, String type, {String? certificateType}) async {
    // Create a DocumentItem from the certificate for the renewal dialog
    // For SIRB, COC, and License: separate person's name from certificate/license type
    String certName;
    String? crewName;
    
    if (type == 'sirb') {
      // For SIRB: name field contains person's name, no separate type field
      crewName = cert['name']?.toString() ?? '';
      certName = 'SIRB'; // SIRB is the type itself
    } else if (type == 'competency') {
      // For COC: name field contains person's name, position field contains certificate type (e.g., "2ND OFFICER")
      crewName = cert['name']?.toString() ?? '';
      // Certificate type for COC is the position (e.g., "2ND OFFICER", "CHIEF OFFICER", etc.)
      certName = cert['position'] ?? cert['certificateType'] ?? cert['name'] ?? 'Unknown Certificate';
    } else if (type == 'license') {
      // For License: name field contains person's name, licenseType contains the license type
      crewName = cert['name']?.toString() ?? '';
      certName = cert['licenseType'] ?? cert['name'] ?? 'Unknown License';
    } else {
      certName = certificateType ?? cert['certificateType'] ?? cert['name'] ?? 'Unknown Certificate';
    }
    String? expiryDate;
    bool hasExpiry = false;
    
    if (type == 'noExpiry') {
      hasExpiry = false;
    } else if (type == 'expiry') {
      expiryDate = cert['dateExpiry']?.toString();
      hasExpiry = expiryDate != null && expiryDate.isNotEmpty;
    } else if (type == 'sirb') {
      expiryDate = cert['seafarerIdExpiry'] ?? cert['dateExpiry']?.toString();
      // SIRB certificates always have expiry dates, even if not set yet
      hasExpiry = true;
    } else if (type == 'competency') {
      expiryDate = cert['seafarerIdExpiry'] ?? cert['expiryDate'] ?? cert['dateExpiry']?.toString();
      // COC certificates always have expiry dates, even if not set yet
      hasExpiry = true;
    } else if (type == 'license') {
      // Check all possible fields for license expiry date (consistent with display logic)
      expiryDate = cert['licenseExpiry'] ?? 
                   cert['dateExpiry'] ?? 
                   cert['expiryDate']?.toString();
      // License certificates always have expiry dates, even if not set yet
      hasExpiry = true;
    }
    
    String? fileUrl = cert['certificateFileUrl'] ?? 
                     cert['fileUrl'] ?? 
                     cert['url'] ?? 
                     cert['downloadURL'] ?? 
                     cert['cloudinaryUrl'] ?? 
                     cert['seafarerIdFileUrl'];
    
    String docType = type == 'noExpiry' ? 'No Expiry' : 
                     type == 'expiry' ? 'With Expiry' :
                     type == 'sirb' ? 'SIRB' :
                     type == 'competency' ? 'Certificate of Competency' :
                     'License';
    String category = (type == 'noExpiry' || type == 'expiry') ? 'Ship Certificates' : 'Officers & Crew';
    
    final DocumentItem docItem = DocumentItem(
      id: '${widget.vesselId}_${type}_${cert.hashCode}',
      name: certName,
      type: docType,
      category: category,
      vesselId: widget.vesselId,
      vesselName: (_vesselData?['vesselName'] ?? widget.vesselData['vesselName'] ?? 'Unknown Vessel').toString(),
      expiryDate: expiryDate,
      issuedDate: cert['dateIssued']?.toString(),
      fileUrl: fileUrl,
      hasExpiry: hasExpiry,
      crewName: crewName, // Pass crew member name for SIRB, COC, License
    );
    
    if (mounted) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => DocumentRenewalDialog(
          document: docItem,
          vesselId: widget.vesselId,
        ),
      );
      
      if (result == true) {
        // Refresh the vessel data from Firestore
        await _loadVesselData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Certificate updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  // Show dialog to select certificate type when adding crew
  void _showAddCrewDialog() {
    final data = _vesselData ?? widget.vesselData;
    final officersCrew = data['officersCrew'] as List? ?? [];
    final competencyCertificates = data['competencyCertificates'] as List? ?? [];
    final competencyLicenses = data['competencyLicenses'] as List? ?? [];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Add Crew Member',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select the certificate type for this crew member:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              // SIRB option
              ListTile(
                leading: Icon(Icons.badge, color: Colors.blue.shade700),
                title: const Text('SIRB', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  'Seafarer Identification and Record Book (${officersCrew.length})',
              style: const TextStyle(fontSize: 12),
            ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue.shade700),
                onTap: () {
                      Navigator.of(context).pop();
                  // Show Add Crew Member dialog for SIRB
                  showDialog(
                context: context,
                builder: (context) => AddCrewMemberDialog(
                  vesselId: widget.vesselId,
                  certificateType: 'SIRB',
                ),
                  ).then((result) {
                if (result == true) {
                  // Refresh vessel data after adding crew member
                  _loadVesselData();
                }
              });
              },
          ),
              const Divider(),
              // COC option
              ListTile(
                leading: Icon(Icons.card_membership, color: Colors.green.shade700),
                title: const Text('COC', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  'Certificate of Competency (${competencyCertificates.length})',
              style: const TextStyle(fontSize: 12),
            ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.green.shade700),
                onTap: () {
                      Navigator.of(context).pop();
                  // Show Add Crew Member dialog for COC
                  showDialog(
                context: context,
                builder: (context) => AddCrewMemberDialog(
                  vesselId: widget.vesselId,
                  certificateType: 'COC',
                ),
                  ).then((result) {
                if (result == true) {
                  // Refresh vessel data after adding crew member
                  _loadVesselData();
                }
              });
              },
          ),
              const Divider(),
              // License option
              ListTile(
                leading: Icon(Icons.verified, color: Colors.orange.shade700),
                title: const Text('License', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  'License Certificate (${competencyLicenses.length})',
              style: const TextStyle(fontSize: 12),
            ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.orange.shade700),
                onTap: () {
                      Navigator.of(context).pop();
                  // Show Add Crew Member dialog for License
                  showDialog(
                context: context,
                builder: (context) => AddCrewMemberDialog(
                  vesselId: widget.vesselId,
                  certificateType: 'License',
                ),
                  ).then((result) {
                if (result == true) {
                  // Refresh vessel data after adding crew member
                  _loadVesselData();
                }
              });
              },
          ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep5Tab() {
    // Step 5: Officers & Crew (HIGHLIGHTED)
    final data = _vesselData ?? widget.vesselData;
    final officersCrew = data['officersCrew'] as List? ?? [];
    final competencyCertificates = data['competencyCertificates'] as List? ?? [];
    final competencyLicenses = data['competencyLicenses'] as List? ?? [];

    return Column(
      children: [
        // Highlighted Header for Step 5
        Container(
          color: Colors.orange.withOpacity(0.1),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.person, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step 5: Officers & Crew',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[900],
                      ),
                    ),
                    Text(
                      'Review all crew members and their certificates',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
          const SizedBox(height: 12),
          // Add Crew Button - Unified button to add crew with certificate type selection
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _showAddCrewDialog,
              icon: const Icon(Icons.person_add, size: 20),
              label: const Text(
                'Add Crew',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        Expanded(
          child: Column(
            children: [
              Container(
                color: Colors.grey[200],
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _crewTabIndex = 0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _crewTabIndex == 0 ? Colors.blue : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: _crewTabIndex == 0 ? Colors.blue : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'SIRB (${officersCrew.length})',
                              style: TextStyle(
                                color: _crewTabIndex == 0 ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _crewTabIndex = 1),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _crewTabIndex == 1 ? Colors.green : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: _crewTabIndex == 1 ? Colors.green : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'COC (${competencyCertificates.length})',
                              style: TextStyle(
                                color: _crewTabIndex == 1 ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _crewTabIndex = 2),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _crewTabIndex == 2 ? Colors.orange : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: _crewTabIndex == 2 ? Colors.orange : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'License (${competencyLicenses.length})',
                              style: TextStyle(
                                color: _crewTabIndex == 2 ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _crewTabIndex,
                  children: [
                    _buildCrewList(officersCrew, 'SIRB'),
                    _buildCrewList(competencyCertificates, 'Certificate of Competency'),
                    _buildCrewList(competencyLicenses, 'License'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCrewList(List<dynamic> crewList, String type) {
    if (crewList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No $type entries',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: crewList.length,
      itemBuilder: (context, index) {
        final member = crewList[index] as Map<String, dynamic>;
        
        // Determine status based on expiry date
        Color statusColor = Colors.green;
        String statusText = 'Valid';
        
        // Check different expiry fields depending on type
        String? expiryField;
        if (type == 'SIRB') {
          expiryField = member['seafarerIdExpiry'] ?? member['dateExpiry'];
        } else if (type == 'Certificate of Competency') {
          expiryField = member['certificateExpiry'] ?? member['dateExpiry'];
        } else {
          expiryField = member['licenseExpiry'] ?? member['dateExpiry'];
        }
        
        if (expiryField != null && expiryField.toString().isNotEmpty) {
          try {
            DateTime expiryDate;
            final dateStr = expiryField.toString();
            
            if (dateStr.contains('/')) {
              final parts = dateStr.split('/');
              if (parts.length == 3) {
                expiryDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
              } else {
                expiryDate = DateTime.parse(dateStr);
              }
            } else {
              expiryDate = DateTime.parse(dateStr);
            }
            
            if (expiryDate.isBefore(now)) {
              statusColor = Colors.red;
              statusText = 'Expired';
            } else if (expiryDate.isBefore(thirtyDaysFromNow)) {
              statusColor = Colors.orange;
              statusText = 'Expiring Soon';
            } else {
              statusColor = Colors.green;
              statusText = 'Valid';
            }
          } catch (e) {
            // If date parsing fails, assume valid
            statusColor = Colors.green;
            statusText = 'Valid';
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        member['name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (member['position'] != null && member['position'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Position: ${member['position']}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ],
                if (expiryField != null && expiryField.toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Expiry: $expiryField',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                if (type == 'License' && member['licenseType'] != null && member['licenseType'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'License Type: ${member['licenseType']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                // Check for uploaded files
                if (member['certificateFileUrl'] != null || member['fileUrl'] != null || member['seafarerIdFileUrl'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.attach_file, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                              onTap: () {
                            final fileUrl = member['certificateFileUrl'] ?? 
                                           member['fileUrl'] ?? 
                                           member['seafarerIdFileUrl'];
                            _viewFile(fileUrl);
                            },
                          child: Text(
                            'View Document',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Update/Renew Button
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (type == 'SIRB') {
                            _updateCertificate(member, 'sirb');
                          } else if (type == 'Certificate of Competency') {
                            _updateCertificate(member, 'competency');
                          } else {
                            _updateCertificate(member, 'license');
                          }
                          },
                        icon: const Icon(Icons.update, size: 18),
                        label: Text(
                          statusText == 'Expired' ? 'Renew' : 'Update',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: statusText == 'Expired' ? Colors.red : const Color(0xFF0A4D68),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF0A4D68),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? 'N/A',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPsscCard({
    required String authorizedCrew,
    required String othersNumber,
    required String passengerAccommodation,
  }) {
    // Calculate total: Authorized Crew + Others
    int? authorizedCrewInt = int.tryParse(authorizedCrew);
    int? othersNumberInt = int.tryParse(othersNumber);
    final total = (authorizedCrewInt ?? 0) + (othersNumberInt ?? 0);
    final totalString = total > 0 ? total.toString() : 'N/A';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow('Passenger with Accommodation', passengerAccommodation),
            _buildPsscRow('Authorized Crew', authorizedCrew, isHighlighted: true),
            _buildPsscRow('Others (Support)', othersNumber, isHighlighted: true),
            const Divider(height: 24, thickness: 1),
            _buildPsscRow('TOTAL', totalString, isHighlighted: true, isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPsscRow(String label, String value, {bool isHighlighted = false, bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isTotal ? 4 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                color: isHighlighted ? Colors.green[700] : Colors.grey[700],
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isHighlighted ? Colors.green[700] : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedSection(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.orange[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManningTable(List<List<String>> rows) {
    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: [
              _buildTableCell('POSITION', isHeader: true),
              _buildTableCell('LICENSE', isHeader: true),
              _buildTableCell('NUMBER', isHeader: true),
            ],
          ),
          ...rows.map((row) => TableRow(
            children: row.map((cell) => _buildTableCell(cell)).toList(),
          )),
        ],
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isHeader ? 12 : 13,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? Colors.black87 : Colors.black87,
        ),
      ),
    );
  }
}



