import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';

class AddVesselScreen extends StatefulWidget {
  const AddVesselScreen({super.key});

  @override
  State<AddVesselScreen> createState() => _AddVesselScreenState();
}

class _AddVesselScreenState extends State<AddVesselScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vesselNameController = TextEditingController();
  final _imoNumberController = TextEditingController();
  final _vesselTypeController = TextEditingController();
  final _companyController = TextEditingController();
  final _contactNumberController = TextEditingController();
  
  String _selectedVesselType = 'Cargo Vessel';
  bool _isSubmitting = false;

  final List<String> _vesselTypes = [
    'Cargo Vessel',
    'Tanker',
    'Passenger Vessel',
    'Fishing Vessel',
    'MTUG',
    'Barge',
    'Other'
  ];

  @override
  void dispose() {
    _vesselNameController.dispose();
    _imoNumberController.dispose();
    _vesselTypeController.dispose();
    _companyController.dispose();
    _contactNumberController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?['uid'];

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Check if vessel already exists
      final existingVessels = await FirebaseFirestore.instance
          .collection('vessels')
          .where('imoNumber', isEqualTo: _imoNumberController.text.trim())
          .get();

      if (existingVessels.docs.isNotEmpty) {
        _showErrorDialog('Vessel Already Exists', 
            'A vessel with IMO number ${_imoNumberController.text.trim()} already exists.');
        return;
      }

      // Create vessel document
      final vesselData = {
        'vesselName': _vesselNameController.text.trim(),
        'imoNumber': _imoNumberController.text.trim(),
        'vesselType': _selectedVesselType,
        'companyOwner': _companyController.text.trim(),
        'contactNumber': _contactNumberController.text.trim(),
        // Store both userId (web standard) and clientId (mobile backward compatibility)
        'userId': userId,
        'clientId': userId,
        'createdAt': DateTime.now().toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
        'certificates': [],
        'status': 'active',
      };

      await FirebaseFirestore.instance
          .collection('vessels')
          .add(vesselData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vessel added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      print('Error adding vessel: $error');
      _showErrorDialog('Error', 'Failed to add vessel: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Vessel'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Fill in the vessel information to register a new vessel',
                          style: TextStyle(color: Colors.blue[900]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Vessel Name
              TextFormField(
                controller: _vesselNameController,
                decoration: InputDecoration(
                  labelText: 'Vessel Name *',
                  prefixIcon: const Icon(Icons.sailing),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter vessel name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // IMO Number
              TextFormField(
                controller: _imoNumberController,
                decoration: InputDecoration(
                  labelText: 'IMO Number *',
                  prefixIcon: const Icon(Icons.tag),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  helperText: '7-digit IMO number',
                ),
                keyboardType: TextInputType.number,
                maxLength: 7,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter IMO number';
                  }
                  if (value.trim().length != 7) {
                    return 'IMO number must be 7 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Vessel Type
              DropdownButtonFormField<String>(
                value: _selectedVesselType,
                decoration: InputDecoration(
                  labelText: 'Vessel Type *',
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _vesselTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVesselType = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Company/Owner
              TextFormField(
                controller: _companyController,
                decoration: InputDecoration(
                  labelText: 'Company/Owner *',
                  prefixIcon: const Icon(Icons.business),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter company/owner name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Contact Number
              TextFormField(
                controller: _contactNumberController,
                decoration: InputDecoration(
                  labelText: 'Contact Number',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  helperText: 'Optional',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 32),

              // Submit Button
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A4D68),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save),
                          SizedBox(width: 12),
                          Text(
                            'Add Vessel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),

              // Info
              Text(
                'Note: More detailed vessel information can be added later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
