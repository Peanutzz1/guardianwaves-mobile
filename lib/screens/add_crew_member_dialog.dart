import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/ocr_service.dart';
import '../services/data_extraction_service.dart';
import '../services/cloudinary_service.dart';
import 'package:intl/intl.dart';

class AddCrewMemberDialog extends StatefulWidget {
  final String vesselId;
  final String certificateType; // 'SIRB', 'COC', or 'License'

  const AddCrewMemberDialog({
    super.key,
    required this.vesselId,
    required this.certificateType,
  });

  @override
  State<AddCrewMemberDialog> createState() => _AddCrewMemberDialogState();
}

class _AddCrewMemberDialogState extends State<AddCrewMemberDialog> {
  final ImagePicker _imagePicker = ImagePicker();
  final OCRService _ocrService = OCRService();
  final DataExtractionService _dataExtractionService = DataExtractionService();
  
  // Changed to support multiple photos (2-3)
  List<XFile> _selectedImages = [];
  List<File> _imageFiles = [];
  bool _isScanning = false;
  bool _isUploading = false;
  bool _isSaving = false;
  
  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _certificateTypeController = TextEditingController();
  final TextEditingController _dateIssuedController = TextEditingController();
  final TextEditingController _dateExpiryController = TextEditingController();
  
  DateTime? _selectedDateIssued;
  DateTime? _selectedDateExpiry;

  // Position list for SIRB and COC (Certificate of Competency)
  static const List<String> _positionList = [
    'MASTER',
    'CHIEF OFFICER',
    'DECK OFFICER',
    '2ND OFFICER',
    '3RD OFFICER',
    'CHIEF ENGINEER',
    '2ND MARINE ENGINEER',
    '3RD MARINE ENGINEER',
    '4TH MARINE ENGINEER',
    'ABLE SEAMAN',
    'OILER',
    'BOSUN',
    'ORDINARY SEAMAN',
    'RADIO OPERATOR',
    'CRANE OPERATOR',
    'DECK CADET',
    'ENGINE CADET',
    'APPRENTICE MATE',
    'CHIEF COOK',
  ];

  // License types list
  static const List<String> _licenseTypes = [
    '2ND MATE',
    '2ND MARINE ENGINEER',
    '3RD MATE',
    '3RD MARINE ENGINEER',
    '4TH MARINE ENGINEER',
    'BOAT CAPTAIN 2',
    'BOAT CAPTAIN 1',
    'CHIEF MATE',
    'CHIEF ENGINEER',
    'MAJOR PATRON',
    'MINOR PATRON',
    'MARINE DIESEL MECHANIC 2',
    'MARINE DIESEL MECHANIC 1',
    'MARINE ENGINE MECHANIC 3',
    'MARINE ENGINE MECHANIC 2',
    'MARINE ENGINE MECHANIC 1',
    'MOTORMAN',
    'MASTER MARINER',
    'OIC-NAVIGATIONAL WATCH',
    'OIC-ENGINEERING WATCH',
  ];

  @override
  void initState() {
    super.initState();
    
    // Set default certificate type based on widget.certificateType
    // For SIRB and COC, leave empty for position selection
    // For License, leave empty for license type selection
    _certificateTypeController.text = '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _certificateTypeController.dispose();
    _dateIssuedController.dispose();
    _dateExpiryController.dispose();
    super.dispose();
  }

  DateTime? _parseDateString(String dateStr) {
    if (dateStr.isEmpty) return null;
    
    try {
      // Try dd/MM/yyyy format first
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          final day = int.parse(parts[0].trim());
          final month = int.parse(parts[1].trim());
          final year = int.parse(parts[2].trim());
          return DateTime(year, month, day);
        }
      }
      // Try ISO format (yyyy-MM-dd)
      return DateTime.parse(dateStr);
    } catch (e) {
      debugPrint('Error parsing date: $dateStr - $e');
      return null;
    }
  }

  Future<void> _selectDateIssued() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateIssued ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      setState(() {
        _selectedDateIssued = picked;
        _dateIssuedController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _selectDateExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    
    if (picked != null) {
      setState(() {
        _selectedDateExpiry = picked;
        _dateExpiryController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final int remainingSlots = 3 - _selectedImages.length;
      if (remainingSlots <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 3 photos allowed'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (source == ImageSource.gallery) {
        // Allow picking multiple images from gallery
        final List<XFile> images = await _imagePicker.pickMultiImage(
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (images.isNotEmpty) {
          final int totalPhotos = _selectedImages.length + images.length;
          if (totalPhotos > 3) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('You can only add ${3 - _selectedImages.length} more photo(s)'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            // Take only the allowed number
            setState(() {
              _selectedImages.addAll(images.take(3 - _selectedImages.length));
              _imageFiles.addAll(images.take(3 - _selectedImages.length).map((img) => File(img.path)));
            });
          } else {
            setState(() {
              _selectedImages.addAll(images);
              _imageFiles.addAll(images.map((img) => File(img.path)));
            });
          }
        }
      } else {
        // Camera - single image
        final XFile? image = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          setState(() {
            _selectedImages.add(image);
            _imageFiles.add(File(image.path));
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _imageFiles.removeAt(index);
    });
  }

  Future<void> _scanCertificate() async {
    if (_imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one image first')),
      );
      return;
    }

    setState(() => _isScanning = true);

    try {
      // Scan the first image
      final result = await _ocrService.recognizeText(_imageFiles[0].path);
      final extractedText = result['text'] as String;

      if (extractedText.isEmpty) {
        if (mounted) {
          setState(() => _isScanning = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not extract text from image')),
          );
        }
        return;
      }

      // Extract data based on certificate type
      if (widget.certificateType == 'SIRB') {
        final extractedData = _dataExtractionService.extractCrewData(extractedText);
        setState(() {
          if (extractedData['name'] != null) {
            _nameController.text = extractedData['name']!;
          }
          // For SIRB, extract position if available
          if (extractedData['position'] != null) {
            _certificateTypeController.text = extractedData['position']!;
          }
          if (extractedData['dateIssued'] != null) {
            _selectedDateIssued = _parseDateString(extractedData['dateIssued']!);
            if (_selectedDateIssued != null) {
              _dateIssuedController.text = DateFormat('dd/MM/yyyy').format(_selectedDateIssued!);
            }
          }
          if (extractedData['dateExpiry'] != null || extractedData['expiryDate'] != null) {
            final expiryStr = extractedData['dateExpiry'] ?? extractedData['expiryDate'];
            _selectedDateExpiry = _parseDateString(expiryStr!);
            if (_selectedDateExpiry != null) {
              _dateExpiryController.text = DateFormat('dd/MM/yyyy').format(_selectedDateExpiry!);
            }
          }
          _isScanning = false;
        });
      } else if (widget.certificateType == 'COC') {
        final extractedData = _dataExtractionService.extractCOCData(extractedText);
        setState(() {
          if (extractedData['name'] != null) {
            _nameController.text = extractedData['name']!;
          }
          if (extractedData['position'] != null) {
            _certificateTypeController.text = extractedData['position']!;
          }
          if (extractedData['dateIssued'] != null) {
            _selectedDateIssued = _parseDateString(extractedData['dateIssued']!);
            if (_selectedDateIssued != null) {
              _dateIssuedController.text = DateFormat('dd/MM/yyyy').format(_selectedDateIssued!);
            }
          }
          if (extractedData['dateExpiry'] != null || extractedData['expiryDate'] != null) {
            final expiryStr = extractedData['dateExpiry'] ?? extractedData['expiryDate'];
            _selectedDateExpiry = _parseDateString(expiryStr!);
            if (_selectedDateExpiry != null) {
              _dateExpiryController.text = DateFormat('dd/MM/yyyy').format(_selectedDateExpiry!);
            }
          }
          _isScanning = false;
        });
      } else if (widget.certificateType == 'License') {
        // Use extractCrewData for license extraction (similar format)
        final extractedData = _dataExtractionService.extractCrewData(extractedText);
        setState(() {
          if (extractedData['name'] != null) {
            _nameController.text = extractedData['name']!;
          }
          // For License, try to extract license type from licenseType, certificateType, or position field
          if (extractedData['licenseType'] != null) {
            _certificateTypeController.text = extractedData['licenseType']!;
          } else if (extractedData['certificateType'] != null) {
            _certificateTypeController.text = extractedData['certificateType']!;
          } else if (extractedData['position'] != null) {
            _certificateTypeController.text = extractedData['position']!;
          }
          if (extractedData['dateIssued'] != null) {
            _selectedDateIssued = _parseDateString(extractedData['dateIssued']!);
            if (_selectedDateIssued != null) {
              _dateIssuedController.text = DateFormat('dd/MM/yyyy').format(_selectedDateIssued!);
            }
          }
          if (extractedData['dateExpiry'] != null || extractedData['expiryDate'] != null) {
            final expiryStr = extractedData['dateExpiry'] ?? extractedData['expiryDate'];
            _selectedDateExpiry = _parseDateString(expiryStr!);
            if (_selectedDateExpiry != null) {
              _dateExpiryController.text = DateFormat('dd/MM/yyyy').format(_selectedDateExpiry!);
            }
          }
          _isScanning = false;
        });
      }
    } catch (e) {
      debugPrint('Error scanning certificate: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning certificate: $e')),
        );
      }
    }
  }

  String _getDialogTitle() {
    switch (widget.certificateType) {
      case 'SIRB':
        return 'Add SIRB Crew Member';
      case 'COC':
        return 'Add COC Certificate';
      case 'License':
        return 'Add License';
      default:
        return 'Add Crew Member';
    }
  }

  String _getCertificateTypeLabel() {
    switch (widget.certificateType) {
      case 'SIRB':
        return 'Position *';
      case 'COC':
        return 'Position *';
      case 'License':
        return 'License Type *';
      default:
        return 'Certificate Type *';
    }
  }

  String _determineStatus(String? expiryDateStr) {
    if (expiryDateStr == null || expiryDateStr.isEmpty) {
      return 'VALID';
    }
    
    try {
      DateTime expiryDate;
      if (expiryDateStr.contains('/')) {
        final parts = expiryDateStr.split('/');
        if (parts.length == 3) {
          final day = int.parse(parts[0].trim());
          final month = int.parse(parts[1].trim());
          final year = int.parse(parts[2].trim());
          expiryDate = DateTime(year, month, day);
        } else {
          expiryDate = DateTime.parse(expiryDateStr);
        }
      } else {
        expiryDate = DateTime.parse(expiryDateStr);
      }
      
      final now = DateTime.now();
      final nowStart = DateTime(now.year, now.month, now.day);
      final expiryStart = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
      final thirtyDaysFromNow = nowStart.add(const Duration(days: 30));
      
      if (expiryStart.isBefore(nowStart)) {
        return 'EXPIRED';
      } else if (expiryStart.isBefore(thirtyDaysFromNow) || expiryStart.isAtSameMomentAs(thirtyDaysFromNow)) {
        return 'EXPIRING SOON';
      } else {
        return 'VALID';
      }
    } catch (e) {
      return 'VALID';
    }
  }

  Future<void> _handleSave() async {
    // Validate required fields
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }

    if (_certificateTypeController.text.trim().isEmpty) {
      final fieldName = widget.certificateType == 'License' 
          ? 'license type' 
          : 'position';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select $fieldName')),
      );
      return;
    }

    if (_dateIssuedController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date issued')),
      );
      return;
    }

    if (_dateExpiryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date expiry')),
      );
      return;
    }

    if (_imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload at least one certificate file'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      List<String> fileUrls = [];
      
      // Upload all images if selected
      if (_imageFiles.isNotEmpty) {
        setState(() => _isUploading = true);
        for (var imageFile in _imageFiles) {
          final fileUrl = await CloudinaryService.uploadCertificate(
            file: imageFile,
            vesselId: widget.vesselId,
          );
          fileUrls.add(fileUrl);
        }
        setState(() => _isUploading = false);
      }

      // Format dates
      final dateIssuedFormatted = _dateIssuedController.text.trim();
      final dateExpiryFormatted = _dateExpiryController.text.trim();
      final certificateStatus = _determineStatus(dateExpiryFormatted);

      // Add to Firestore
      await _addCrewMemberToFirebase(
        dateIssuedFormatted,
        dateExpiryFormatted,
        certificateStatus,
        fileUrls,
      );

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.certificateType} crew member added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      debugPrint('Error adding crew member: $error');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add crew member: $error')),
        );
      }
    }
  }

  Future<void> _addCrewMemberToFirebase(
    String dateIssued,
    String dateExpiry,
    String status,
    List<String> fileUrls,
  ) async {
    // For backward compatibility, use first URL as primary
    final String primaryFileUrl = fileUrls.isNotEmpty ? fileUrls[0] : '';
    final vesselDoc = await FirebaseFirestore.instance
        .collection('vessels')
        .doc(widget.vesselId)
        .get();

    if (!vesselDoc.exists) {
      throw Exception('Vessel not found');
    }

    final vesselData = vesselDoc.data() as Map<String, dynamic>;
    
    final newMember = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'name': _nameController.text.trim(),
      'dateIssued': dateIssued,
      'dateExpiry': dateExpiry,
      'expiryDate': dateExpiry,
      'status': status,
      'remarks': status,
    };

    if (primaryFileUrl.isNotEmpty) {
      newMember['fileUrl'] = primaryFileUrl;
      newMember['certificateFileUrl'] = primaryFileUrl;
      newMember['photoUrls'] = fileUrls; // Store all photo URLs
      
      if (widget.certificateType == 'SIRB') {
        newMember['seafarerIdFileUrl'] = primaryFileUrl;
      }
    }

    if (widget.certificateType == 'SIRB') {
      newMember['position'] = _certificateTypeController.text.trim(); // Position for SIRB
      newMember['seafarerIdExpiry'] = dateExpiry;
      
      final officersCrew = List<Map<String, dynamic>>.from(
        vesselData['officersCrew'] ?? []
      );
      officersCrew.add(newMember);
      
      await FirebaseFirestore.instance
          .collection('vessels')
          .doc(widget.vesselId)
          .update({
        'officersCrew': officersCrew,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } else if (widget.certificateType == 'COC') {
      newMember['position'] = _certificateTypeController.text.trim();
      newMember['certificateExpiry'] = dateExpiry;
      newMember['seafarerIdExpiry'] = dateExpiry;
      
      final competencyCertificates = List<Map<String, dynamic>>.from(
        vesselData['competencyCertificates'] ?? []
      );
      competencyCertificates.add(newMember);
      
      await FirebaseFirestore.instance
          .collection('vessels')
          .doc(widget.vesselId)
          .update({
        'competencyCertificates': competencyCertificates,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } else if (widget.certificateType == 'License') {
      newMember['licenseType'] = _certificateTypeController.text.trim();
      newMember['licenseExpiry'] = dateExpiry;
      
      final competencyLicenses = List<Map<String, dynamic>>.from(
        vesselData['competencyLicenses'] ?? []
      );
      competencyLicenses.add(newMember);
      
      await FirebaseFirestore.instance
          .collection('vessels')
          .doc(widget.vesselId)
          .update({
        'competencyLicenses': competencyLicenses,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getDialogTitle(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Form Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Upload Certificate File
                    const Text(
                      'Upload Certificate File (Max 3)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Photo counter
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Photos',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_selectedImages.length}/3',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Display selected photos in grid
                    if (_selectedImages.isNotEmpty) ...[
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: _selectedImages.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _imageFiles[index],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removePhoto(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    
                    // Upload buttons
                    if (_selectedImages.length < 3) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Capture'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Maximum 3 photos reached',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // Scan button (only show if at least one photo is selected)
                    if (_selectedImages.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _isScanning ? null : _scanCertificate,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.scanner),
                        label: Text(_isScanning ? 'Scanning...' : 'Scan & Extract Data (First Photo)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Name Field
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Name *',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Certificate Type/Position/License Type Field
                    widget.certificateType == 'SIRB' || widget.certificateType == 'COC'
                        ? DropdownButtonFormField<String>(
                            value: _certificateTypeController.text.isEmpty
                                ? null
                                : _certificateTypeController.text,
                            decoration: InputDecoration(
                              labelText: _getCertificateTypeLabel(),
                              prefixIcon: const Icon(Icons.badge),
                              border: OutlineInputBorder(),
                            ),
                            isExpanded: true,
                            items: _positionList.map((String position) {
                              return DropdownMenuItem<String>(
                                value: position,
                                child: Text(
                                  position,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _certificateTypeController.text = newValue ?? '';
                              });
                            },
                          )
                        : widget.certificateType == 'License'
                            ? DropdownButtonFormField<String>(
                                value: _certificateTypeController.text.isEmpty
                                    ? null
                                    : _certificateTypeController.text,
                                decoration: InputDecoration(
                                  labelText: _getCertificateTypeLabel(),
                                  prefixIcon: const Icon(Icons.badge),
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                                items: _licenseTypes.map((String license) {
                                  return DropdownMenuItem<String>(
                                    value: license,
                                    child: Text(
                                      license,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _certificateTypeController.text = newValue ?? '';
                                  });
                                },
                              )
                            : TextFormField(
                                controller: _certificateTypeController,
                                decoration: InputDecoration(
                                  labelText: _getCertificateTypeLabel(),
                                  prefixIcon: const Icon(Icons.badge),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                    const SizedBox(height: 16),
                    // Date Issued
                    TextFormField(
                      controller: _dateIssuedController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Date Issued *',
                        prefixIcon: const Icon(Icons.calendar_today),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                        border: OutlineInputBorder(),
                      ),
                      onTap: _selectDateIssued,
                    ),
                    const SizedBox(height: 16),
                    // Date Expiry
                    TextFormField(
                      controller: _dateExpiryController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Date Expiry *',
                        prefixIcon: const Icon(Icons.calendar_today),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                        border: OutlineInputBorder(),
                      ),
                      onTap: _selectDateExpiry,
                    ),
                  ],
                ),
              ),
            ),
            // Action Buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving || _isUploading ? null : _handleSave,
                    icon: _isUploading || _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isUploading
                        ? 'Uploading...'
                        : _isSaving
                            ? 'Saving...'
                            : 'Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

