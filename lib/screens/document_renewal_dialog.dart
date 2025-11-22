import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/ocr_service.dart';
import '../services/data_extraction_service.dart';
import '../services/cloudinary_service.dart';
import 'package:intl/intl.dart';
import '../models/document_item.dart';

class DocumentRenewalDialog extends StatefulWidget {
  final DocumentItem document;
  final String vesselId;

  const DocumentRenewalDialog({
    super.key,
    required this.document,
    required this.vesselId,
  });

  @override
  State<DocumentRenewalDialog> createState() => _DocumentRenewalDialogState();
}

class _DocumentRenewalDialogState extends State<DocumentRenewalDialog> {
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
  final TextEditingController _nameController = TextEditingController(); // For crew member name (SIRB, COC, License)
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
    
    // For SIRB, COC, and License: use crewName for name field, name for position/type field
    // For other certificates: use name for certificate type field
    final isCrewDocument = widget.document.type == 'SIRB' || 
                          widget.document.type == 'Certificate of Competency' ||
                          widget.document.type == 'License';
    
    if (isCrewDocument && widget.document.crewName != null) {
      // Crew member documents: separate name and position/type
      _nameController.text = widget.document.crewName!;
      // For SIRB and COC, document.name might contain the position
      // For License, document.name contains the license type
      if (widget.document.type == 'SIRB' || widget.document.type == 'Certificate of Competency') {
        // Check if document.name is a valid position, otherwise leave empty
        final docName = widget.document.name.trim();
        if (docName.isNotEmpty && _positionList.contains(docName)) {
          _certificateTypeController.text = docName;
        } else {
          _certificateTypeController.text = '';
        }
      } else if (widget.document.type == 'License') {
        // Check if document.name is a valid license type, otherwise leave empty
        final docName = widget.document.name.trim();
        if (docName.isNotEmpty && _licenseTypes.contains(docName)) {
          _certificateTypeController.text = docName;
        } else {
          _certificateTypeController.text = '';
        }
      } else {
        _certificateTypeController.text = widget.document.name;
      }
    } else {
      // Regular certificates: name goes to certificate type field
      _certificateTypeController.text = widget.document.name;
    }
    
    if (widget.document.issuedDate != null) {
      _selectedDateIssued = _parseDateString(widget.document.issuedDate.toString());
      // Format the date consistently to dd/MM/yyyy for display
      if (_selectedDateIssued != null) {
        _dateIssuedController.text = DateFormat('dd/MM/yyyy').format(_selectedDateIssued!);
      } else {
        _dateIssuedController.text = widget.document.issuedDate.toString();
      }
    }
    if (widget.document.hasExpiry) {
      // If expiry date exists, use it; otherwise leave empty (user must select)
      if (widget.document.expiryDate != null && widget.document.expiryDate.toString().isNotEmpty) {
        final expiryDateStr = widget.document.expiryDate.toString().trim();
        debugPrint('Parsing expiry date: $expiryDateStr');
        _selectedDateExpiry = _parseDateString(expiryDateStr);
        // Format the date consistently to dd/MM/yyyy for display
        if (_selectedDateExpiry != null) {
          _dateExpiryController.text = DateFormat('dd/MM/yyyy').format(_selectedDateExpiry!);
          debugPrint('Successfully parsed and formatted expiry date: ${_dateExpiryController.text}');
        } else {
          // If parsing fails, try to use the date string as-is (might already be in correct format)
          debugPrint('Failed to parse expiry date, using original string: $expiryDateStr');
          _dateExpiryController.text = expiryDateStr;
        }
      } else {
        debugPrint('No expiry date found in document');
      }
      // If hasExpiry is true but no expiry date, leave field empty for user to select
    }
    // Removed focus listeners - using onTap instead to avoid conflicts
  }

  @override
  void dispose() {
    _nameController.dispose();
    _certificateTypeController.dispose();
    _dateIssuedController.dispose();
    _dateExpiryController.dispose();
    super.dispose();
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $error'),
            backgroundColor: Colors.red,
          ),
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

  Future<void> _scanDocument() async {
    if (_imageFiles.isEmpty) return;

    setState(() {
      _isScanning = true;
    });

    try {
      // Perform OCR on the first image
      final result = await _ocrService.recognizeText(_imageFiles[0].path);
      final extractedText = result['text'] as String;
      
      // Extract certificate data based on document type
      Map<String, dynamic> certificateData;
      final isCrewDoc = widget.document.type == 'SIRB' || 
                       widget.document.type == 'Certificate of Competency' ||
                       widget.document.type == 'License';
      
      if (widget.document.type == 'Certificate of Competency') {
        certificateData = _dataExtractionService.extractCOCData(extractedText);
      } else if (isCrewDoc) {
        certificateData = _dataExtractionService.extractCrewData(extractedText);
      } else {
        certificateData = _dataExtractionService.extractCertificateData(extractedText);
      }
      
      // Auto-populate fields
      if (mounted) {
        setState(() {
          final isCrewDoc = widget.document.type == 'SIRB' || 
                          widget.document.type == 'Certificate of Competency' ||
                          widget.document.type == 'License';
          
          // Populate name field for crew documents
          if (isCrewDoc && certificateData['name'] != null) {
            _nameController.text = certificateData['name'] as String;
          }
          
          // Populate position/certificate/license type field
          // For SIRB and COC, check for position field first, then certificateType
          if (widget.document.type == 'SIRB' || widget.document.type == 'Certificate of Competency') {
            if (certificateData['position'] != null) {
              final position = (certificateData['position'] as String).trim();
              // Only set if it's in the valid position list
              if (_positionList.contains(position)) {
                _certificateTypeController.text = position;
              }
            } else if (certificateData['certificateType'] != null) {
              final certType = (certificateData['certificateType'] as String).trim();
              // Only set if it's in the valid position list
              if (_positionList.contains(certType)) {
                _certificateTypeController.text = certType;
              }
            }
          } else if (widget.document.type == 'License') {
            // For License, check for licenseType field first, then certificateType
            if (certificateData['licenseType'] != null) {
              final licenseType = (certificateData['licenseType'] as String).trim();
              // Only set if it's in the valid license types list
              if (_licenseTypes.contains(licenseType)) {
                _certificateTypeController.text = licenseType;
              }
            } else if (certificateData['certificateType'] != null) {
              final certType = (certificateData['certificateType'] as String).trim();
              // Only set if it's in the valid license types list
              if (_licenseTypes.contains(certType)) {
                _certificateTypeController.text = certType;
              }
            }
          } else if (certificateData['certificateType'] != null) {
            _certificateTypeController.text = certificateData['certificateType'] as String;
          }
          
          if (certificateData['dateIssued'] != null) {
            _dateIssuedController.text = certificateData['dateIssued'] as String;
            // Try to parse the date
            _selectedDateIssued = _parseDateString(certificateData['dateIssued'] as String);
          }
          
          if (certificateData['dateExpiry'] != null) {
            _dateExpiryController.text = certificateData['dateExpiry'] as String;
            // Try to parse the date
            _selectedDateExpiry = _parseDateString(certificateData['dateExpiry'] as String);
          }
          
          _isScanning = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificate data extracted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to scan document: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  DateTime? _parseDateString(String dateStr) {
    try {
      // Trim whitespace
      dateStr = dateStr.trim();
      
      // Format: "YYYY-MM-DD" (ISO format)
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          // Handle YYYY-MM-DD format
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          return DateTime(year, month, day);
        }
        // Try standard DateTime.parse for other dash formats
        return DateTime.parse(dateStr);
      }
      // Format: "DD/MM/YYYY"
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          // Assume DD/MM/YYYY
          return DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      }
      // Try standard DateTime.parse as fallback
      return DateTime.parse(dateStr);
    } catch (e) {
      // Error parsing date
      debugPrint('Error parsing date: $e');
    }
    return null;
  }

  Future<void> _selectDateIssued() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateIssued ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      // Update immediately with a small delay to avoid blocking UI
      setState(() {
        _selectedDateIssued = picked;
        _dateIssuedController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _selectDateExpiry() async {
    debugPrint('_selectDateExpiry called');
    try {
      final DateTime now = DateTime.now();
      final DateTime defaultDate = now.add(const Duration(days: 365));
      
      // Ensure initialDate is not before firstDate (DateTime.now())
      DateTime initialDate;
      if (_selectedDateExpiry != null) {
        // If the selected date is in the past, use today or default date
        if (_selectedDateExpiry!.isBefore(now)) {
          initialDate = defaultDate;
          debugPrint('Selected date is expired, using default date: $initialDate');
        } else {
          initialDate = _selectedDateExpiry!;
        }
      } else {
        initialDate = defaultDate;
      }
      
      debugPrint('Initial date: $initialDate');
      debugPrint('First date: $now');
      debugPrint('Showing date picker...');
      
      if (!mounted) {
        debugPrint('Widget not mounted, returning');
        return;
      }
      
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365 * 10)),
      );
      
      debugPrint('Date picker returned: $picked');
      
      if (picked != null && mounted) {
        setState(() {
          _selectedDateExpiry = picked;
          _dateExpiryController.text = DateFormat('dd/MM/yyyy').format(picked);
        });
        debugPrint('Date updated: ${_dateExpiryController.text}');
      }
    } catch (e, stackTrace) {
      debugPrint('Error selecting expiry date: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening date picker: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadAndSave() async {
    if (_imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload at least one certificate file'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate name field for crew documents
    final isCrewDocument = widget.document.type == 'SIRB' || 
                          widget.document.type == 'Certificate of Competency' ||
                          widget.document.type == 'License';
    if (isCrewDocument && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Validate position/certificate type field
    if (_certificateTypeController.text.trim().isEmpty) {
      final fieldName = widget.document.type == 'License' 
          ? 'license type' 
          : (widget.document.type == 'SIRB' || widget.document.type == 'Certificate of Competency')
              ? 'position'
              : 'certificate type';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select $fieldName'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // For documents with expiry, validate expiry date
    if (widget.document.hasExpiry && _dateExpiryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter expiry date'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _isSaving = true;
    });

    try {
      // Upload all files to Cloudinary
      List<String> fileUrls = [];
      for (var imageFile in _imageFiles) {
        final fileUrl = await CloudinaryService.uploadCertificate(
          file: imageFile,
          vesselId: widget.vesselId,
          certificateId: widget.document.id,
        );
        fileUrls.add(fileUrl);
      }

      // Update the document in Firebase with multiple photo URLs
      debugPrint('🔄 Starting Firebase update...');
      await _updateDocumentInFirebase(fileUrls);
      debugPrint('✅ Firebase update completed successfully');

      if (mounted) {
        // Wait a moment to ensure Firestore has processed the update
        await Future.delayed(const Duration(milliseconds: 500));
        
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificate renewed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('❌ Error renewing certificate: $error');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to renew certificate: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _updateDocumentInFirebase(List<String> fileUrls) async {
    // For backward compatibility, use first URL as primary
    final String primaryFileUrl = fileUrls.isNotEmpty ? fileUrls[0] : '';
    try {
      final vesselDoc = await FirebaseFirestore.instance
          .collection('vessels')
          .doc(widget.vesselId)
          .get();

      if (!vesselDoc.exists) {
        throw Exception('Vessel not found');
      }

      final vesselData = vesselDoc.data() as Map<String, dynamic>;
      
      // Helper function to convert date to dd/MM/yyyy format for display consistency
      String formatDateForDisplay(DateTime? date, String textValue) {
        if (date != null) {
          // Use dd/MM/yyyy format for consistency with UI display
          return DateFormat('dd/MM/yyyy').format(date);
        } else if (textValue.isNotEmpty) {
          // Try to parse and reformat text input
          try {
            final parts = textValue.split('/');
            if (parts.length == 3) {
              // Already in dd/MM/yyyy format
              return textValue;
            } else {
              // Try parsing as ISO format (yyyy-MM-dd) or other formats
              final parsedDate = DateTime.parse(textValue);
              return DateFormat('dd/MM/yyyy').format(parsedDate);
            }
          } catch (e) {
            // If parsing fails, return as-is
            debugPrint('Warning: Could not parse date: $textValue');
            return textValue;
          }
        }
        return '';
      }

      // Helper function to determine certificate status based on expiry date
      String determineStatus(String? expiryDateStr) {
        if (expiryDateStr == null || expiryDateStr.isEmpty) {
          debugPrint('⚠️ No expiry date provided, returning VALID');
          return 'VALID';
        }
        
        try {
          DateTime expiryDate;
          if (expiryDateStr.contains('/')) {
            final parts = expiryDateStr.split('/');
            if (parts.length == 3) {
              // Handle dd/MM/yyyy format
              final day = int.parse(parts[0].trim());
              final month = int.parse(parts[1].trim());
              final year = int.parse(parts[2].trim());
              expiryDate = DateTime(year, month, day);
            } else {
              expiryDate = DateTime.parse(expiryDateStr);
            }
          } else if (expiryDateStr.contains('-')) {
            // Handle ISO format or other dash formats
            expiryDate = DateTime.parse(expiryDateStr);
          } else {
            // Try parsing as-is
            expiryDate = DateTime.parse(expiryDateStr);
          }
          
          final now = DateTime.now();
          // Set time to start of day for accurate comparison
          final nowStart = DateTime(now.year, now.month, now.day);
          final expiryStart = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
          final thirtyDaysFromNow = nowStart.add(const Duration(days: 30));
          
          debugPrint('📅 Status calculation:');
          debugPrint('   Expiry date: $expiryStart');
          debugPrint('   Current date: $nowStart');
          debugPrint('   30 days from now: $thirtyDaysFromNow');
          
          String status;
          if (expiryStart.isBefore(nowStart)) {
            status = 'EXPIRED';
          } else if (expiryStart.isBefore(thirtyDaysFromNow) || expiryStart.isAtSameMomentAs(thirtyDaysFromNow)) {
            status = 'EXPIRING SOON';
          } else {
            status = 'VALID';
          }
          
          debugPrint('   Determined status: $status');
          return status;
        } catch (e, stackTrace) {
          debugPrint('❌ Error determining status: $e');
          debugPrint('   Stack trace: $stackTrace');
          debugPrint('   Expiry date string: $expiryDateStr');
          // Default to VALID if parsing fails
          return 'VALID';
        }
      }
      
      // Determine which array contains this document based on document type/category
      // Update the appropriate certificate array
      // Use dd/MM/yyyy format for display consistency
      final String dateIssuedFormatted = formatDateForDisplay(_selectedDateIssued, _dateIssuedController.text);
      
      // For expiry date, prioritize the selected date over the text controller
      String dateExpiryFormatted;
      if (_selectedDateExpiry != null) {
        // Use the selected date directly to ensure accuracy
        dateExpiryFormatted = DateFormat('dd/MM/yyyy').format(_selectedDateExpiry!);
      } else if (_dateExpiryController.text.isNotEmpty) {
        // Fallback to text controller if no date selected
        dateExpiryFormatted = formatDateForDisplay(null, _dateExpiryController.text);
      } else {
        // If no expiry date provided but document has expiry, use existing expiry date
        dateExpiryFormatted = widget.document.expiryDate?.toString() ?? '';
      }
      
      debugPrint('🔄 Updating certificate - Document type: ${widget.document.type}, Category: ${widget.document.category}');
      debugPrint('📄 Document name: ${widget.document.name}');
      debugPrint('📅 Date Issued formatted: $dateIssuedFormatted');
      debugPrint('📅 Date Expiry formatted: $dateExpiryFormatted');
      debugPrint('📅 Date Expiry controller text: ${_dateExpiryController.text}');
      debugPrint('📅 Selected expiry date: $_selectedDateExpiry');
      
      // Determine status based on expiry date - use selected date if available
      String certificateStatus;
      if (_selectedDateExpiry != null) {
        // Use selected date for accurate status calculation
        certificateStatus = determineStatus(dateExpiryFormatted);
      } else if (widget.document.hasExpiry && dateExpiryFormatted.isNotEmpty) {
        certificateStatus = determineStatus(dateExpiryFormatted);
      } else {
        certificateStatus = 'VALID';
      }
      
      debugPrint('✅ Certificate status determined: $certificateStatus');

      // Find and update the certificate in the appropriate array
      if (widget.document.type == 'No Expiry') {
        // Update in noExpiryDocs array
        final noExpiryDocs = List<Map<String, dynamic>>.from(
          vesselData['noExpiryDocs'] ?? []
        );
        
        // Find the certificate by name/certificateType (case-insensitive, handle variations)
        final searchName = widget.document.name.toUpperCase().trim();
        final certIndex = noExpiryDocs.indexWhere(
          (cert) {
            final certType = (cert['certificateType'] ?? cert['name'] ?? '').toString().toUpperCase().trim();
            return certType == searchName || certType.contains(searchName) || searchName.contains(certType);
          }
        );
        
        debugPrint('🔍 Searching for No Expiry certificate: $searchName');
        debugPrint('📋 Available certificates: ${noExpiryDocs.map((c) => (c['certificateType'] ?? c['name'] ?? '').toString()).toList()}');
        debugPrint('📍 Found at index: $certIndex');
        
        if (certIndex != -1) {
          // Update existing certificate
          noExpiryDocs[certIndex] = {
            ...noExpiryDocs[certIndex],
            'certificateType': _certificateTypeController.text.trim(),
            'name': _certificateTypeController.text.trim(),
            'dateIssued': dateIssuedFormatted,
            'certificateFileUrl': primaryFileUrl,
            'fileUrl': primaryFileUrl,
            'url': primaryFileUrl,
            'downloadURL': primaryFileUrl,
            'cloudinaryUrl': primaryFileUrl,
            'scannedFileUrl': primaryFileUrl,
            'photoUrls': fileUrls, // Store all photo URLs
            'status': 'VALID',
            'remarks': 'VALID',
          };
        } else {
          // Certificate doesn't exist yet - create it
          debugPrint('📝 Certificate not found, creating new entry');
          final newCertificate = {
            'certificateType': _certificateTypeController.text.trim(),
            'name': _certificateTypeController.text.trim(),
            'dateIssued': dateIssuedFormatted,
            'certificateFileUrl': primaryFileUrl,
            'fileUrl': primaryFileUrl,
            'url': primaryFileUrl,
            'downloadURL': primaryFileUrl,
            'cloudinaryUrl': primaryFileUrl,
            'scannedFileUrl': primaryFileUrl,
            'photoUrls': fileUrls, // Store all photo URLs
            'status': 'VALID',
            'remarks': 'VALID',
          };
          noExpiryDocs.add(newCertificate);
          debugPrint('✅ Created new certificate entry');
        }
        
        await FirebaseFirestore.instance
            .collection('vessels')
            .doc(widget.vesselId)
            .update({
          'noExpiryDocs': noExpiryDocs,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else if (widget.document.type == 'With Expiry' || (widget.document.category == 'Ship Certificates' && widget.document.type != 'No Expiry')) {
        // Update in expiryCertificates array
        final expiryCertificates = List<Map<String, dynamic>>.from(
          vesselData['expiryCertificates'] ?? []
        );
        
        // Improved matching: try multiple strategies to find the certificate
        final searchName = widget.document.name.toUpperCase().trim();
        final searchType = _certificateTypeController.text.trim().toUpperCase();
        
        int certIndex = -1;
        
        // Strategy 1: Exact match by certificateType or name
        certIndex = expiryCertificates.indexWhere(
          (cert) {
            final certType = (cert['certificateType'] ?? cert['name'] ?? '').toString().toUpperCase().trim();
            return certType == searchName || certType == searchType;
          }
        );
        
        // Strategy 2: Partial match (contains)
        if (certIndex == -1) {
          certIndex = expiryCertificates.indexWhere(
            (cert) {
              final certType = (cert['certificateType'] ?? cert['name'] ?? '').toString().toUpperCase().trim();
              return certType.contains(searchName) || searchName.contains(certType) ||
                     certType.contains(searchType) || searchType.contains(certType);
            }
          );
        }
        
        // Strategy 3: Normalize and compare (remove special chars, extra spaces)
        if (certIndex == -1) {
          final normalize = (String s) => s.replaceAll(RegExp(r'[^\w]'), '').replaceAll(RegExp(r'\s+'), '');
          final normalizedSearch = normalize(searchName);
          certIndex = expiryCertificates.indexWhere(
            (cert) {
              final certType = (cert['certificateType'] ?? cert['name'] ?? '').toString();
              final normalizedCert = normalize(certType.toUpperCase());
              return normalizedCert == normalizedSearch || 
                     normalizedCert.contains(normalizedSearch) || 
                     normalizedSearch.contains(normalizedCert);
            }
          );
        }
        
        debugPrint('🔍 Searching for Expiry certificate: $searchName');
        debugPrint('📋 Available certificates: ${expiryCertificates.map((c) => (c['certificateType'] ?? c['name'] ?? '').toString()).toList()}');
        debugPrint('📍 Found at index: $certIndex');
        
        if (certIndex != -1) {
          // Preserve all existing fields and update only what's needed
          final existingCert = expiryCertificates[certIndex];
          expiryCertificates[certIndex] = {
            ...existingCert, // Preserve all existing fields
            'certificateType': _certificateTypeController.text.trim(),
            'name': _certificateTypeController.text.trim(),
            'dateIssued': dateIssuedFormatted,
            'dateExpiry': dateExpiryFormatted,
            'certificateFileUrl': primaryFileUrl,
            'fileUrl': primaryFileUrl,
            'url': primaryFileUrl,
            'downloadURL': primaryFileUrl,
            'cloudinaryUrl': primaryFileUrl,
            'scannedFileUrl': primaryFileUrl,
            'photoUrls': fileUrls, // Store all photo URLs
            'status': certificateStatus,
            'remarks': certificateStatus,
            'hasExpiry': true, // Ensure hasExpiry is set
          };
          
          debugPrint('✅ Updating certificate at index $certIndex');
          debugPrint('📝 Updated data: ${expiryCertificates[certIndex]}');
          
          // Perform the update
          final updateData = {
            'expiryCertificates': expiryCertificates,
            'lastUpdated': FieldValue.serverTimestamp(),
          };
          
          debugPrint('💾 Writing to Firestore...');
          debugPrint('   Vessel ID: ${widget.vesselId}');
          debugPrint('   Update data keys: ${updateData.keys.toList()}');
          
          await FirebaseFirestore.instance
              .collection('vessels')
              .doc(widget.vesselId)
              .update(updateData);
          
          // Verify the update by reading back the document
          final verifyDoc = await FirebaseFirestore.instance
              .collection('vessels')
              .doc(widget.vesselId)
              .get();
          
          if (verifyDoc.exists) {
            final verifyData = verifyDoc.data();
            final verifyCerts = verifyData?['expiryCertificates'] as List? ?? [];
            if (certIndex < verifyCerts.length) {
              final verifyCert = verifyCerts[certIndex] as Map<String, dynamic>;
              debugPrint('✅ Verification - Updated certificate:');
              debugPrint('   certificateType: ${verifyCert['certificateType']}');
              debugPrint('   dateExpiry: ${verifyCert['dateExpiry']}');
              debugPrint('   status: ${verifyCert['status']}');
            }
          }
          
          debugPrint('✅ Successfully updated certificate in Firestore');
        } else {
          debugPrint('❌ Certificate NOT FOUND!');
          debugPrint('Search name: $searchName');
          debugPrint('Search type: $searchType');
          debugPrint('Available certificates:');
          for (var i = 0; i < expiryCertificates.length; i++) {
            final cert = expiryCertificates[i];
            debugPrint('  [$i] certificateType: ${cert['certificateType']}, name: ${cert['name']}');
          }
          throw Exception('Certificate not found in vessel data. Please update manually from vessel edit screen.');
        }
      } else if (widget.document.type == 'Certificate of Competency') {
        // Update in competencyCertificates array
        final competencyCertificates = List<Map<String, dynamic>>.from(
          vesselData['competencyCertificates'] ?? []
        );
        
        // For COC: match by crew member name (from crewName field), not document name (which is position)
        final searchName = (widget.document.crewName ?? widget.document.name ?? '').toString().toUpperCase().trim();
        
        debugPrint('🔍 Searching for COC certificate with crew name: $searchName');
        debugPrint('📋 Available COC certificates: ${competencyCertificates.map((c) => '${c['name']} (position: ${c['position']})').toList()}');
        
        final certIndex = competencyCertificates.indexWhere(
          (cert) {
            final certName = (cert['name'] ?? '').toString().toUpperCase().trim();
            // Also try matching by position if name doesn't match (fallback)
            final certPosition = (cert['position'] ?? '').toString().toUpperCase().trim();
            final docName = widget.document.name.toUpperCase().trim();
            return certName == searchName || (searchName.isEmpty && certPosition == docName);
          }
        );
        
        debugPrint('📍 Found COC certificate at index: $certIndex');
        
        if (certIndex != -1) {
          // For COC: name field contains person's name, position field contains certificate type (position)
          competencyCertificates[certIndex] = {
            ...competencyCertificates[certIndex],
            'name': _nameController.text.trim(),
            'position': _certificateTypeController.text.trim(), // Certificate type is the position for COC
            'dateIssued': dateIssuedFormatted,
            'seafarerIdExpiry': dateExpiryFormatted,
            'certificateExpiry': dateExpiryFormatted,
            'expiryDate': dateExpiryFormatted,
            'certificateFileUrl': primaryFileUrl,
            'fileUrl': primaryFileUrl,
            'photoUrls': fileUrls, // Store all photo URLs
            'status': certificateStatus,
            'remarks': certificateStatus,
          };
          
          await FirebaseFirestore.instance
              .collection('vessels')
              .doc(widget.vesselId)
              .update({
            'competencyCertificates': competencyCertificates,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          
          debugPrint('✅ Successfully updated COC certificate in Firestore');
          debugPrint('Updated certificate data: ${competencyCertificates[certIndex]}');
        } else {
          throw Exception('Certificate not found in vessel data. Please update manually from vessel edit screen.');
        }
      } else if (widget.document.type == 'License') {
        // Update in competencyLicenses array
        final competencyLicenses = List<Map<String, dynamic>>.from(
          vesselData['competencyLicenses'] ?? []
        );
        
        // For License: match by crew member name (from crewName field) first, then by licenseType
        final searchCrewName = (widget.document.crewName ?? '').toString().toUpperCase().trim();
        final searchLicenseType = widget.document.name.toUpperCase().trim();
        
        debugPrint('🔍 Searching for License with crew name: $searchCrewName, licenseType: $searchLicenseType');
        debugPrint('📋 Available licenses: ${competencyLicenses.map((l) => '${l['name']} (licenseType: ${l['licenseType']})').toList()}');
        debugPrint('📝 Document details - name: ${widget.document.name}, crewName: ${widget.document.crewName}, type: ${widget.document.type}');
        
        final licenseIndex = competencyLicenses.indexWhere(
          (license) {
            // Match by crew member name first (primary for License)
            final licenseName = (license['name'] ?? '').toString().toUpperCase().trim();
            if (searchCrewName.isNotEmpty && licenseName == searchCrewName) {
              debugPrint('✅ Matched by crew name: $licenseName');
              return true;
            }
            // Match by licenseType as fallback
            final licenseType = (license['licenseType'] ?? '').toString().toUpperCase().trim();
            if (licenseType == searchLicenseType || licenseType.contains(searchLicenseType) || searchLicenseType.contains(licenseType)) {
              debugPrint('✅ Matched by licenseType: $licenseType');
              return true;
            }
            
            return false;
          }
        );
        
        debugPrint('📍 Found License at index: $licenseIndex');
        if (licenseIndex == -1) {
          debugPrint('❌ License NOT FOUND! Document name: "${widget.document.name}", crewName: "${widget.document.crewName}"');
          debugPrint('Available licenseTypes: ${competencyLicenses.map((l) => l['licenseType']).where((t) => t != null).toList()}');
          debugPrint('Available names: ${competencyLicenses.map((l) => l['name']).where((n) => n != null).toList()}');
        }
        
        if (licenseIndex != -1) {
          // For License: name field contains person's name, licenseType contains license type
          competencyLicenses[licenseIndex] = {
            ...competencyLicenses[licenseIndex],
            'licenseType': _certificateTypeController.text.trim(),
            'name': _nameController.text.trim(),
            'dateIssued': dateIssuedFormatted,
            'licenseExpiry': dateExpiryFormatted,
            'expiryDate': dateExpiryFormatted,
            'certificateFileUrl': primaryFileUrl,
            'fileUrl': primaryFileUrl,
            'photoUrls': fileUrls, // Store all photo URLs
            'status': certificateStatus,
            'remarks': certificateStatus,
          };
          
          await FirebaseFirestore.instance
              .collection('vessels')
              .doc(widget.vesselId)
              .update({
            'competencyLicenses': competencyLicenses,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          
          debugPrint('✅ Successfully updated License in Firestore');
          debugPrint('Updated license data: ${competencyLicenses[licenseIndex]}');
        } else {
          throw Exception('License not found in vessel data. Please update manually from vessel edit screen.');
        }
      } else if (widget.document.type == 'SIRB' || widget.document.category == 'Officers & Crew') {
        // Try to find in officersCrew array (for SIRB)
        final officersCrew = List<Map<String, dynamic>>.from(
          vesselData['officersCrew'] ?? []
        );
        
        // For SIRB: match by crew member name (from crewName field), not document name (which is "SIRB")
        final searchName = (widget.document.crewName ?? widget.document.name ?? '').toString().toUpperCase().trim();
        
        debugPrint('🔍 Searching for SIRB crew member with name: $searchName');
        debugPrint('📋 Available crew members: ${officersCrew.map((m) => m['name']).toList()}');
        debugPrint('📝 Document crewName: ${widget.document.crewName}, name: ${widget.document.name}');
        
        final crewIndex = officersCrew.indexWhere(
          (member) {
            final memberName = (member['name'] ?? '').toString().toUpperCase().trim();
            return memberName == searchName;
          }
        );
        
        debugPrint('📍 Found crew member at index: $crewIndex');
        
        if (crewIndex != -1) {
          // Update SIRB entry - name field contains person's name, position field contains position
          officersCrew[crewIndex] = {
            ...officersCrew[crewIndex],
            'name': _nameController.text.trim(),
            'position': _certificateTypeController.text.trim(), // Position for SIRB
            'dateIssued': dateIssuedFormatted,
            'seafarerIdExpiry': dateExpiryFormatted,
            'expiryDate': dateExpiryFormatted,
            'seafarerIdFileUrl': primaryFileUrl,
            'certificateFileUrl': primaryFileUrl,
            'fileUrl': primaryFileUrl,
            'photoUrls': fileUrls, // Store all photo URLs
            'status': certificateStatus,
            'remarks': certificateStatus,
          };
          
          await FirebaseFirestore.instance
              .collection('vessels')
              .doc(widget.vesselId)
              .update({
            'officersCrew': officersCrew,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          
          debugPrint('✅ Successfully updated SIRB crew member in Firestore');
          debugPrint('Updated crew member data: ${officersCrew[crewIndex]}');
        } else {
          // If not found in officersCrew, try competencyCertificates (for COC)
          final competencyCertificates = List<Map<String, dynamic>>.from(
            vesselData['competencyCertificates'] ?? []
          );
          
          // For COC fallback: match by crew member name
          final searchCrewName = (widget.document.crewName ?? widget.document.name ?? '').toString().toUpperCase().trim();
          
          debugPrint('🔍 Searching for COC certificate (fallback) with crew name: $searchCrewName');
          debugPrint('📋 Available COC certificates: ${competencyCertificates.map((c) => '${c['name']} (position: ${c['position']})').toList()}');
          
          final certIndex = competencyCertificates.indexWhere(
            (cert) {
              final certName = (cert['name'] ?? '').toString().toUpperCase().trim();
              return certName == searchCrewName;
            }
          );
          
          debugPrint('📍 Found COC certificate (fallback) at index: $certIndex');
          
          if (certIndex != -1) {
            // For COC fallback: name controller for person's name, certificate type is position
            competencyCertificates[certIndex] = {
              ...competencyCertificates[certIndex],
              'name': _nameController.text.trim(),
              'position': _certificateTypeController.text.trim(), // Certificate type is the position for COC
              'dateIssued': dateIssuedFormatted,
              'seafarerIdExpiry': dateExpiryFormatted,
              'certificateExpiry': dateExpiryFormatted,
              'expiryDate': dateExpiryFormatted,
              'certificateFileUrl': primaryFileUrl,
              'fileUrl': primaryFileUrl,
              'photoUrls': fileUrls, // Store all photo URLs
              'status': certificateStatus,
              'remarks': certificateStatus,
            };
            
            await FirebaseFirestore.instance
                .collection('vessels')
                .doc(widget.vesselId)
                .update({
              'competencyCertificates': competencyCertificates,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
            
            debugPrint('✅ Successfully updated COC certificate (fallback) in Firestore');
            debugPrint('Updated certificate data: ${competencyCertificates[certIndex]}');
          } else {
            throw Exception('Document not found in vessel data. Please update manually from vessel edit screen.');
          }
        }
      }
    } catch (error) {
      debugPrint('Error updating document in Firebase: $error');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                children: [
                  const Icon(Icons.update, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Renew Certificate',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          // For crew documents (SIRB, COC, License), show crew name; otherwise show certificate name
                          (widget.document.type == 'SIRB' || 
                           widget.document.type == 'Certificate of Competency' ||
                           widget.document.type == 'License') && widget.document.crewName != null
                              ? widget.document.crewName!
                              : widget.document.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
            
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Upload Image Section
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Upload Certificate File',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            // Photo counter
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Photos (Max 3)',
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
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF0A4D68),
                                        side: const BorderSide(color: Color(0xFF0A4D68)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _pickImage(ImageSource.gallery),
                                      icon: const Icon(Icons.photo_library),
                                      label: const Text('Gallery'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF0A4D68),
                                        side: const BorderSide(color: Color(0xFF0A4D68)),
                                      ),
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
                                onPressed: _isScanning ? null : _scanDocument,
                                icon: _isScanning
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.document_scanner),
                                label: Text(_isScanning ? 'Scanning...' : 'Scan & Extract Data (First Photo)'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0A4D68),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Name field (for SIRB, COC, License)
                    if (widget.document.type == 'SIRB' || 
                        widget.document.type == 'Certificate of Competency' ||
                        widget.document.type == 'License')
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                    
                    if (widget.document.type == 'SIRB' || 
                        widget.document.type == 'Certificate of Competency' ||
                        widget.document.type == 'License')
                      const SizedBox(height: 16),
                    
                    // Certificate Type / Position / License Type
                    widget.document.type == 'Certificate of Competency' || widget.document.type == 'SIRB'
                        ? DropdownButtonFormField<String>(
                            value: _certificateTypeController.text.isEmpty || 
                                   !_positionList.contains(_certificateTypeController.text)
                                ? null
                                : _certificateTypeController.text,
                            decoration: const InputDecoration(
                              labelText: 'Position *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.badge),
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
                        : widget.document.type == 'License'
                            ? DropdownButtonFormField<String>(
                                value: _certificateTypeController.text.isEmpty || 
                                       !_licenseTypes.contains(_certificateTypeController.text)
                                    ? null
                                    : _certificateTypeController.text,
                                decoration: const InputDecoration(
                                  labelText: 'License Type *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.badge),
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
                            : TextField(
                                controller: _certificateTypeController,
                                decoration: const InputDecoration(
                                  labelText: 'Certificate Type *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.description),
                                ),
                              ),
                    
                    const SizedBox(height: 16),
                    
                    // Date Issued
                    InkWell(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        _selectDateIssued();
                      },
                      child: IgnorePointer(
                        ignoring: true,
                        child: TextFormField(
                          controller: _dateIssuedController,
                          readOnly: true,
                          enabled: true,
                          decoration: const InputDecoration(
                            labelText: 'Date Issued *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today),
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Date Expiry (only show if document has expiry)
                    if (widget.document.hasExpiry)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          debugPrint('Date Expiry tapped!');
                          FocusScope.of(context).unfocus();
                          _selectDateExpiry();
                        },
                        child: IgnorePointer(
                          ignoring: true,
                          child: TextFormField(
                            controller: _dateExpiryController,
                            readOnly: true,
                            enabled: true,
                            decoration: const InputDecoration(
                              labelText: 'Date Expiry *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.event),
                              suffixIcon: Icon(Icons.arrow_drop_down),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // Action Buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _uploadAndSave,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isUploading ? 'Uploading...' : 'Save Renewal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
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

