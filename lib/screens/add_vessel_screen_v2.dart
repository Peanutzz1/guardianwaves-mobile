import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shipping_companies.dart';
import '../providers/auth_provider.dart';
import '../services/cloudinary_service.dart';
import '../services/data_extraction_service.dart';
import '../services/ocr_service.dart';
import '../widgets/vessel_submission_success_dialog.dart';
import 'approval_status_screen.dart';
import 'manning_requirements_screen.dart';

class AddVesselScreenV2 extends StatefulWidget {
  final String? vesselId;
  final Map<String, dynamic>? vesselData;
  final int? initialStep; // Optional initial step to start at
  final int? initialCrewTabIndex; // Optional crew tab index for Step 5

  const AddVesselScreenV2({super.key, this.vesselId, this.vesselData, this.initialStep, this.initialCrewTabIndex});

  @override
  State<AddVesselScreenV2> createState() => _AddVesselScreenV2State();
}

class _AddVesselScreenV2State extends State<AddVesselScreenV2> {
  int _currentStep = 0;
  bool _isSubmitting = false;
  bool _isEditMode = false;
  bool _isLoadingData = false; // Loading state for edit mode
  int _crewTabIndex = 0; // For Step 5 filter tabs
  bool _shouldLaunchManningEditor = false;

  // Debouncing timer for text field validation
  Timer? _debounceTimer;
  Timer? _draftSaveDebounce;

  // Cached dropdown items to prevent rebuilding on every frame
  late final List<DropdownMenuItem<String>> _vesselTypeItems;
  late final List<DropdownMenuItem<String>> _companyItems;
  late final List<DropdownMenuItem<String>> _hullMaterialItems;
  late final Set<String> _validCompanyNames; // For O(1) lookup
  late final Set<String> _validVesselTypes; // For O(1) lookup
  late final Set<String> _validHullMaterials; // For O(1) lookup
  late final Map<String, String> _companyNameToCode; // For O(1) code lookup
  static const String _draftStorageKey = 'add_vessel_form_v2_draft';
  bool _isRestoringDraft = false;
  bool _shouldPersistDraftOnDispose = true;
  late final List<TextEditingController> _step1Controllers;

  @override
  void initState() {
    super.initState();

    // Set initial step if provided
    if (widget.initialStep != null) {
      _currentStep = widget.initialStep!;
    }
    if (widget.initialCrewTabIndex != null) {
      _crewTabIndex = widget.initialCrewTabIndex!;
    }

    // Initialize cached dropdown items once
    _vesselTypeItems = [
      const DropdownMenuItem<String>(
        value: null,
        child: Text('Select Vessel Type'),
        enabled: false,
      ),
      ..._vesselTypes.map(
        (type) => DropdownMenuItem<String>(
          value: type,
          child: Text(type, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    _validVesselTypes = _vesselTypes.toSet();

    _companyItems = [
      const DropdownMenuItem<String>(
        value: null,
        child: Text('Select Company/Owner'),
        enabled: false,
      ),
      ...ShippingCompanies.companies.map(
        (company) => DropdownMenuItem<String>(
          value: company.name,
          child: Text(company.name, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    _validCompanyNames = ShippingCompanies.companies.map((c) => c.name).toSet();
    _companyNameToCode = Map.fromEntries(
      ShippingCompanies.companies.map((c) => MapEntry(c.name, c.code)),
    );

    _hullMaterialItems = [
      const DropdownMenuItem<String>(
        value: null,
        child: Text('Select Hull Material'),
        enabled: false,
      ),
      ..._hullMaterials.map(
        (material) =>
            DropdownMenuItem<String>(value: material, child: Text(material)),
      ),
    ];

    _validHullMaterials = _hullMaterials.toSet();

    _step1Controllers = [
      _vesselNameController,
      _imoNumberController,
      _shippingCodeController,
      _contactNumberController,
      _masterController,
      _chiefEngineerController,
    ];

    for (final controller in _step1Controllers) {
      controller.addListener(_onDraftFieldChanged);
    }

    _isEditMode = widget.vesselId != null && widget.vesselData != null;
    if (_isEditMode) {
      // Show loading state and load data asynchronously
      setState(() {
        _isLoadingData = true;
      });
      // Load existing vessel data into form asynchronously after frame is rendered
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Add a small delay to allow UI to render loading state
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted) {
          // Load data asynchronously in chunks to prevent UI blocking
          await Future.microtask(() => _loadExistingVesselData());
          if (mounted) {
            setState(() {
              _isLoadingData = false;
            });
          }
        }
      });
    } else {
      unawaited(_loadDraft());
    }
  }

  // Step 1: Vessel Information
  late final _vesselNameController = TextEditingController();
  late final _imoNumberController = TextEditingController();
  late final _shippingCodeController = TextEditingController();
  late final _contactNumberController = TextEditingController();
  late final _masterController = TextEditingController();
  late final _chiefEngineerController = TextEditingController();
  String _selectedVesselType = '';
  String _selectedCompanyOwner = '';

  // Validation errors for Step 1
  String? _vesselTypeError;
  String? _vesselNameError;
  String? _imoError;
  String? _companyError;
  String? _shippingCodeError;
  String? _contactNumberError;
  String? _masterError;
  String? _chiefEngineerError;

  // Step 2: General Particulars
  late final _typeOfShipController = TextEditingController(text: 'CARGO SHIP');
  late final _grossTonnageController = TextEditingController();
  late final _netTonnageController = TextEditingController();
  late final _placeBuiltController = TextEditingController();
  late final _yearBuiltController = TextEditingController();
  late final _builderController = TextEditingController();
  late final _lengthController = TextEditingController();
  late final _homeportController = TextEditingController();
  late final _numberOfEnginesController = TextEditingController();
  late final _kilowattController = TextEditingController();
  String _selectedHullMaterial = '';

  // Validation errors for Step 2
  String? _typeOfShipError;
  String? _grossTonnageError;
  String? _netTonnageError;
  String? _placeBuiltError;
  String? _yearBuiltError;
  String? _builderError;
  String? _lengthError;
  String? _homeportError;
  String? _hullMaterialError;
  String? _numberOfEnginesError;
  String? _kilowattError;

  // Step 3: Manning Requirements - Deck Department
  List<Map<String, dynamic>> _deckDepartment = [];

  // Step 3: Manning Requirements - Engine Department
  List<Map<String, dynamic>> _engineDepartment = [];

  // File upload states for Step 3
  Map<String, String> _deckFiles = {}; // id -> file path
  Map<String, String> _engineFiles = {}; // id -> file path

  // OCR service
  final OCRService _ocrService = OCRService();
  final ImagePicker _imagePicker = ImagePicker();

  // Step 3: PSSC
  late final _authorizedCrewController = TextEditingController(text: '10');
  late final _othersNumberController = TextEditingController(text: '10');

  // Validation errors for Step 3
  String? _authorizedCrewError;
  String? _othersNumberError;

  // Step 4: Certificates - NO EXPIRY
  late final _philippineRegistryDateController = TextEditingController();
  late final _ownershipDateController = TextEditingController();
  late final _tonnageDateController = TextEditingController();

  // Step 4: Certificates - WITH EXPIRY (dynamic list)
  List<Map<String, dynamic>> _expiryCertificates = [];

  // Step 4: File upload states
  Map<String, String> _noExpiryFiles = {}; // certificate type -> file path
  static const Map<String, String> _noExpiryCertificateLabels = {
    'philippineRegistry': 'Certificate of Philippine Registry',
    'ownership': 'Certificate of Ownership',
    'tonnage': 'Tonnage Measurement',
  };

  static const Map<String, String> _noExpiryCertificateTypes = {
    'philippineRegistry': 'CERTIFICATE OF PHILIPPINE REGISTRY',
    'ownership': 'CERTIFICATE OF OWNERSHIP',
    'tonnage': 'TONNAGE MEASUREMENT',
  };

  static const Map<String, String> _noExpiryLegacyFileKeys = {
    'philippineRegistry': 'philippineRegistryFileUrl',
    'ownership': 'ownershipFileUrl',
    'tonnage': 'tonnageFileUrl',
  };
  Map<String, String> _expiryFiles = {}; // certificate id -> file path

  // Step 5: Officers & Crew - Legacy (kept for backward compatibility)
  List<Map<String, dynamic>> _crewMembers = [];
  Map<String, String> _crewFiles = {}; // crew id -> file path

  // Step 5: Officers & Crew - SIRB (Seafarer Identification and Record Book)
  List<Map<String, dynamic>> _sirbMembers = [];
  Map<String, String> _sirbFiles = {}; // sirb id -> file path

  // Step 5: Officers & Crew - Document Certificate of Competency
  List<Map<String, dynamic>> _competencyCertificates = [];
  Map<String, String> _competencyFiles = {}; // competency id -> file path

  // Step 5: Officers & Crew - License
  List<Map<String, dynamic>> _competencyLicenses = [];
  Map<String, String> _licenseFiles = {}; // license id -> file path

  // Certificate types for dropdown
  final List<String> _certificateTypes = [
    'BAY AND RIVER LICENSE',
    'CARGO SECURING MANUAL COMPLIANCE CERTIFICATE',
    'CARGO SHIP SAFETY CERTIFICATE',
    'CARGO SHIP SAFETY CONSTRUCTION CERTIFICATE',
    'CARGO SHIP SAFETY EQUIPMENT CERTIFICATE',
    'CERTIFICATE OF ACCREDITATION',
    'CERTIFICATE OF PUBLIC CONVENIENCE',
    'CERTIFICATE OF COMPLIANCE',
    'CIVIL LIABILITY FOR OIL POLLUTION CERTIFICATE',
    'CLASSIFICATION CERTIFICATE',
    'COASTWISE LICENSE',
    'DOCUMENT OF COMPLIANCE',
    'EXEMPTION CERTIFICATE',
    'FISHING VESSEL SAFETY CERTIFICATE',
    'INTERIM SAFETY MANAGEMENT CERTIFICATE',
    'LOADLINE CERTIFICATE',
    'MINIMUM SAFE MANNING CERTIFICATE',
    'NATIONAL SHIP SECURITY CERTIFICATE',
    'OIL POLLUTION PREVENTION CERTIFICATE OF COMPLIANCE',
    'PASSENGER SHIP SAFETY CERTIFICATE',
    'PASSENGER INSURANCE COVER',
    'PLEASURE YACHT LICENSE',
    'PROVISIONAL AUTHORITY',
    'RIDER',
    'SAFETY MANAGEMENT CERTIFICATE',
    'SEAWAGE POLLUTION PREVENTION CERTIFICATE',
    'SHIP STATION LICENSE',
    'SPECIAL PERMIT',
    'TOURISM ACCREDITATION CERTIFICATE',
  ];

  // Lists for dropdowns
  final List<String> _positions = [
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

  final List<String> _licenses = [
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

  final List<String> _vesselTypes = [
    'BULK CARRIER',
    'CARGO VESSEL',
    'CONTAINER SHIP',
    'CRUDE OIL TANKER',
    'FISHING VESSEL',
    'GENERAL CARGO VESSEL',
    'LPG TANKER',
    'PASSENGER VESSEL',
    'PRODUCTS TANKER',
    'RO-RO VESSEL',
    'TUG',
    'OTHER',
  ];

  final List<String> _hullMaterials = [
    'STEEL',
    'ALUMINUM',
    'FIBERGLASS',
    'WOOD',
  ];

  // Load existing vessel data for editing
  // Made async to prevent blocking UI thread
  Future<void> _loadExistingVesselData() async {
    if (widget.vesselData == null) return;

    final data = widget.vesselData!;

    // Load Step 1 data
    _vesselNameController.text = data['vesselName']?.toString() ?? '';
    _imoNumberController.text = data['imoNumber']?.toString() ?? '';
    _shippingCodeController.text = data['shippingCode']?.toString() ?? '';
    _contactNumberController.text = data['contactNumber']?.toString() ?? '';
    _masterController.text = data['master']?.toString() ?? '';
    _chiefEngineerController.text = data['chiefEngineer']?.toString() ?? '';

    // Yield to allow UI to update
    await Future.delayed(const Duration(milliseconds: 10));

    final vesselType = data['vesselType']?.toString() ?? '';
    final companyOwner = data['companyOwner']?.toString() ?? '';

    // Load Step 2 data
    _typeOfShipController.text = data['typeOfShip']?.toString() ?? 'CARGO SHIP';
    _grossTonnageController.text = data['grossTonnage']?.toString() ?? '';
    _netTonnageController.text = data['netTonnage']?.toString() ?? '';
    _placeBuiltController.text = data['placeBuilt']?.toString() ?? '';
    _yearBuiltController.text = data['yearBuilt']?.toString() ?? '';
    _builderController.text = data['builder']?.toString() ?? '';
    _lengthController.text = data['length']?.toString() ?? '';
    _homeportController.text = data['homeport']?.toString() ?? '';
    _numberOfEnginesController.text = data['numberOfEngine']?.toString() ?? '';
    _kilowattController.text = data['kilowatt']?.toString() ?? '';
    final hullMaterial = data['hullMaterial']?.toString() ?? '';

    // Yield to allow UI to update
    await Future.delayed(const Duration(milliseconds: 10));

    // Load Step 3 data
    _authorizedCrewController.text = data['authorizedCrew']?.toString() ?? '10';
    _othersNumberController.text = data['othersNumber']?.toString() ?? '10';

    // Load Step 3 Manning Requirements - Deck and Engine Departments
    // Normalize position and license values to match dropdown items
    _deckDepartment = (data['deckDepartment'] as List? ?? [])
        .map((entry) {
          final normalized = Map<String, dynamic>.from(entry);
          if (normalized['position'] != null) {
            normalized['position'] = _getMatchingPosition(
              normalized['position']?.toString(),
            ) ?? normalized['position'];
          }
          if (normalized['license'] != null) {
            normalized['license'] = _getMatchingLicense(
              normalized['license']?.toString(),
            ) ?? normalized['license'];
          }
          return normalized;
        })
        .toList();
    _engineDepartment = (data['engineDepartment'] as List? ?? [])
        .map((entry) {
          final normalized = Map<String, dynamic>.from(entry);
          if (normalized['position'] != null) {
            normalized['position'] = _getMatchingPosition(
              normalized['position']?.toString(),
            ) ?? normalized['position'];
          }
          if (normalized['license'] != null) {
            normalized['license'] = _getMatchingLicense(
              normalized['license']?.toString(),
            ) ?? normalized['license'];
          }
          return normalized;
        })
        .toList();

    // Yield to allow UI to update
    await Future.delayed(const Duration(milliseconds: 10));

    // Load Step 4 data - NO EXPIRY
    // First try to load from noExpiryDocs (new format matching web app)
    final noExpiryDocs = data['noExpiryDocs'] as List? ?? [];

    if (noExpiryDocs.isNotEmpty) {
      // Load from noExpiryDocs array
      for (var doc in noExpiryDocs) {
        final certType = doc['certificateType']?.toString() ?? '';
        final dateIssued = doc['dateIssued']?.toString() ?? '';
        final fileUrl =
            doc['url'] ?? doc['certificateFileUrl'] ?? doc['fileUrl'] ?? '';

        if (certType == 'CERTIFICATE OF PHILIPPINE REGISTRY') {
          _philippineRegistryDateController.text = dateIssued;
          // Note: We can't restore the local file path from URL,
          // but the file will remain accessible via URL
        } else if (certType == 'CERTIFICATE OF OWNERSHIP') {
          _ownershipDateController.text = dateIssued;
        } else if (certType == 'TONNAGE MEASUREMENT') {
          _tonnageDateController.text = dateIssued;
        }
      }
    } else {
      // Fallback to old format (backward compatibility)
      _philippineRegistryDateController.text =
          data['philippineRegistryDate']?.toString() ?? '';
      _ownershipDateController.text = data['ownershipDate']?.toString() ?? '';
      _tonnageDateController.text = data['tonnageDate']?.toString() ?? '';
    }

    // Load Step 4 data - WITH EXPIRY
    _expiryCertificates = List<Map<String, dynamic>>.from(
      data['expiryCertificates'] ?? [],
    );

    // Yield to allow UI to update
    await Future.delayed(const Duration(milliseconds: 10));

    // Load Step 5 data
    _sirbMembers = List<Map<String, dynamic>>.from(data['officersCrew'] ?? []);
    _competencyCertificates = List<Map<String, dynamic>>.from(
      data['competencyCertificates'] ?? [],
    );
    _competencyLicenses = List<Map<String, dynamic>>.from(
      data['competencyLicenses'] ?? [],
    );

    // Yield to allow UI to update before final setState
    await Future.delayed(const Duration(milliseconds: 10));

    // Update state to trigger UI rebuild with loaded values
    if (mounted) {
      setState(() {
        _selectedVesselType = vesselType;
        _selectedCompanyOwner = companyOwner;
        _selectedHullMaterial = hullMaterial;

        // Auto-fill shipping code if company is selected
        if (companyOwner.isNotEmpty) {
          final code = _companyNameToCode[companyOwner];
          if (code != null && code.isNotEmpty) {
            _shippingCodeController.text = code;
          }
        }
      });
    }

    @override
    void dispose() {
      _debounceTimer?.cancel();
      _draftSaveDebounce?.cancel();
      for (final controller in _step1Controllers) {
        controller.removeListener(_onDraftFieldChanged);
      }
      if (_shouldPersistDraftOnDispose) {
        unawaited(_saveDraft());
      }
      _vesselNameController.dispose();
      _imoNumberController.dispose();
      _shippingCodeController.dispose();
      _contactNumberController.dispose();
      _masterController.dispose();
      _chiefEngineerController.dispose();
      _typeOfShipController.dispose();
      _grossTonnageController.dispose();
      _netTonnageController.dispose();
      _placeBuiltController.dispose();
      _yearBuiltController.dispose();
      _builderController.dispose();
      _lengthController.dispose();
      _homeportController.dispose();
      _numberOfEnginesController.dispose();
      _kilowattController.dispose();
      _authorizedCrewController.dispose();
      _othersNumberController.dispose();
      _philippineRegistryDateController.dispose();
      _ownershipDateController.dispose();
      _tonnageDateController.dispose();
      super.dispose();
    }

    // Certificate helper methods
    void _selectCertificateDate(TextEditingController controller) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setState(() {
          controller.text = '${picked.day}/${picked.month}/${picked.year}';
        });
      }
    }

    void _addExpiryCertificate() {
      setState(() {
        _expiryCertificates.add({
          'id': DateTime.now().millisecondsSinceEpoch,
          'certificateType': '',
          'dateIssued': '',
          'dateExpiry': '',
          'status': 'VALID',
        });
      });
    }
  }

  void _deleteExpiryCertificate(int id) {
    setState(() {
      _expiryCertificates.removeWhere((cert) => cert['id'] == id);
      _expiryFiles.remove(id.toString());
    });
  }

  void _updateExpiryCertificate(int id, String field, dynamic value) {
    final index = _expiryCertificates.indexWhere((cert) => cert['id'] == id);
    if (index != -1 && _expiryCertificates[index][field] != value) {
      setState(() {
        _expiryCertificates[index][field] = value;
      });
    }
  }

  void _selectExpiryCertificateDate(int id, String field) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final dateStr = '${picked.day}/${picked.month}/${picked.year}';
      _updateExpiryCertificate(id, field, dateStr);
    }
  }

  // File upload methods for Step 3
  void _uploadFileForMember(String department, int id) async {
    try {
      // Show dialog to choose camera or gallery
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select File Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        if (department == 'deck') {
          _deckFiles[id.toString()] = image.path;
        } else {
          _engineFiles[id.toString()] = image.path;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File uploaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload file'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Calculate totals for Step 3
  int _calculateDeckTotal() {
    return _deckDepartment.fold(0, (sum, entry) {
      final number = int.tryParse(entry['number']?.toString() ?? '0') ?? 0;
      return sum + number;
    });
  }

  int _calculateEngineTotal() {
    return _engineDepartment.fold(0, (sum, entry) {
      final number = int.tryParse(entry['number']?.toString() ?? '0') ?? 0;
      return sum + number;
    });
  }

  // Step 4 helper methods
  String _calculateValidityStatus(String dateIssued) {
    if (dateIssued.isEmpty) return 'NOT SET';

    try {
      final parts = dateIssued.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);

        // Validate date values are reasonable
        if (day < 1 ||
            day > 31 ||
            month < 1 ||
            month > 12 ||
            year < 1900 ||
            year > 2100) {
          return 'INVALID';
        }

        final issuedDate = DateTime(year, month, day);
        final normalizedIssuedDate =
            DateTime(issuedDate.year, issuedDate.month, issuedDate.day);
        final today = DateTime.now();
        final normalizedToday = DateTime(today.year, today.month, today.day);

        final isExactMatch = issuedDate.year == year &&
            issuedDate.month == month &&
            issuedDate.day == day;

        if (isExactMatch && !normalizedIssuedDate.isAfter(normalizedToday)) {
          return 'VALID';
        } else {
          return 'INVALID';
        }
      }
    } catch (e) {
      return 'INVALID';
    }
    return 'NOT SET';
  }

  bool _isNullOrEmpty(Object? value) {
    if (value == null) return true;
    return value.toString().trim().isEmpty;
  }

  bool _hasNoExpirySupportingFile(String certId) {
    final localPath = _noExpiryFiles[certId];
    if (localPath != null && localPath.trim().isNotEmpty) {
      return true;
    }

    if (_isEditMode && widget.vesselData != null) {
      final docs = widget.vesselData!['noExpiryDocs'] as List? ?? [];
      final firestoreType = _noExpiryCertificateTypes[certId];
      if (firestoreType != null) {
        for (final doc in docs) {
          final type = doc['certificateType']?.toString();
          if (type == firestoreType) {
            final url = doc['url'] ??
                doc['certificateFileUrl'] ??
                doc['fileUrl'];
            if (!_isNullOrEmpty(url)) {
              return true;
            }
          }
        }
      }

      final legacyKey = _noExpiryLegacyFileKeys[certId];
      if (legacyKey != null) {
        final legacyUrl = widget.vesselData![legacyKey];
        if (!_isNullOrEmpty(legacyUrl)) {
          return true;
        }
      }
    }

    return false;
  }

  bool _hasSupportingFile(Map<String, dynamic> item, Map<String, String> localFiles) {
    final id = item['id']?.toString();
    if (id != null) {
      final localPath = localFiles[id];
      if (localPath != null && localPath.trim().isNotEmpty) {
        return true;
      }
    }

    const possibleKeys = ['fileUrl', 'certificateFileUrl', 'url', 'documentUrl'];
    for (final key in possibleKeys) {
      final value = item[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;

    try {
      // Try DD/MM/YYYY format first
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          final day = int.parse(parts[0].trim());
          final month = int.parse(parts[1].trim());
          final year = int.parse(parts[2].trim());
          return DateTime(year, month, day);
        }
      }

      // Try parsing as standard date string
      try {
        return DateTime.parse(dateStr);
      } catch (e) {
        // Continue to other formats
      }

      // Try DD Month YYYY format (e.g., "07 September 2042")
      final monthNames = {
        'january': 1,
        'jan': 1,
        'february': 2,
        'feb': 2,
        'march': 3,
        'mar': 3,
        'april': 4,
        'apr': 4,
        'may': 5,
        'june': 6,
        'jun': 6,
        'july': 7,
        'jul': 7,
        'august': 8,
        'aug': 8,
        'september': 9,
        'sep': 9,
        'sept': 9,
        'october': 10,
        'oct': 10,
        'november': 11,
        'nov': 11,
        'december': 12,
        'dec': 12,
      };

      final dateLower = dateStr.toLowerCase().trim();
      for (final entry in monthNames.entries) {
        if (dateLower.contains(entry.key)) {
          // Extract day and year
          final parts = dateLower.split(entry.key);
          if (parts.length >= 2) {
            final dayPart = parts[0].trim().split(RegExp(r'\s+')).last;
            final yearPart = parts[1].trim().split(RegExp(r'\s+')).first;
            final day = int.tryParse(dayPart) ?? 1;
            final year = int.tryParse(yearPart) ?? DateTime.now().year;
            return DateTime(year, entry.value, day);
          }
        }
      }

      // Try other variations like "DD-MM-YYYY" or "YYYY-MM-DD"
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          // If first part is 4 digits, assume YYYY-MM-DD
          if (parts[0].length == 4) {
            final year = int.parse(parts[0].trim());
            final month = int.parse(parts[1].trim());
            final day = int.parse(parts[2].trim());
            return DateTime(year, month, day);
          } else {
            // Assume DD-MM-YYYY
            final day = int.parse(parts[0].trim());
            final month = int.parse(parts[1].trim());
            final year = int.parse(parts[2].trim());
            return DateTime(year, month, day);
          }
        }
      }

      return null;
    } catch (e) {
      print('Error parsing date "$dateStr": $e');
      return null;
    }
  }

  Map<String, int> _calculateExpiryStatus(
    String dateExpiry, {
    String? dateIssued,
  }) {
    if (dateExpiry.isEmpty) return {'days': 0, 'months': 0, 'years': 0};

    try {
      // Parse expiry date using flexible parser
      final expiryDate = _parseDate(dateExpiry);

      if (expiryDate == null) {
        print('Failed to parse expiry date: $dateExpiry');
        return {'days': 0, 'months': 0, 'years': 0};
      }

      // Determine start date: use dateIssued if available, otherwise use today
      DateTime startDate;
      if (dateIssued != null && dateIssued.isNotEmpty) {
        final parsedIssued = _parseDate(dateIssued);
        if (parsedIssued != null) {
          startDate = parsedIssued;
        } else {
          print('Failed to parse issued date: $dateIssued, using today');
          startDate = DateTime.now();
        }
      } else {
        startDate = DateTime.now();
      }

      // Ensure we're using start of day for accurate calculation
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final expiry = DateTime(
        expiryDate.year,
        expiryDate.month,
        expiryDate.day,
      );

      // Calculate total difference in days first
      final difference = expiry.difference(start).inDays;

      if (difference < 0) {
        // Already expired
        return {'days': -1, 'months': 0, 'years': 0};
      }

      // Calculate years, months, and days
      int years = expiry.year - start.year;
      int months = expiry.month - start.month;
      int days = expiry.day - start.day;

      // Adjust for negative days
      if (days < 0) {
        months--;
        // Get days in the previous month
        final prevMonth = expiry.month == 1 ? 12 : expiry.month - 1;
        final prevYear = expiry.month == 1 ? expiry.year - 1 : expiry.year;
        final daysInPrevMonth = DateTime(prevYear, prevMonth + 1, 0).day;
        days += daysInPrevMonth;
      }

      // Adjust for negative months
      if (months < 0) {
        years--;
        months += 12;
      }

      // Ensure non-negative values
      if (years < 0) years = 0;
      if (months < 0) months = 0;
      if (days < 0) days = 0;

      return {'days': days, 'months': months, 'years': years};
    } catch (e) {
      print('Error calculating expiry status: $e');
      return {'days': 0, 'months': 0, 'years': 0};
    }
  }

  String _getExpiryStatusText(Map<String, int> status) {
    final days = status['days']!;
    final months = status['months']!;
    final years = status['years']!;

    if (days < 0 || months < 0 || years < 0) {
      return 'EXPIRED';
    } else if (days <= 30 && months == 0 && years == 0) {
      return 'EXPIRING SOON';
    } else {
      return 'VALID';
    }
  }

  Color _getExpiryStatusColor(String status) {
    switch (status) {
      case 'EXPIRED':
        return Colors.red;
      case 'EXPIRING SOON':
        return Colors.orange;
      case 'VALID':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // File upload methods for Step 4
  void _uploadNoExpiryFile(String certificateType) async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select File Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _noExpiryFiles[certificateType] = image.path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File uploaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload file'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _uploadExpiryFile(int certificateId) async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select File Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _expiryFiles[certificateId.toString()] = image.path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File uploaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload file'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _scanExpiryCertificate(int certificateId) async {
    try {
      // Show dialog to choose camera or gallery
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Scan Certificate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      // Pick image
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Scanning certificate...'),
            ],
          ),
        ),
      );

      try {
        // Process OCR
        final result = await _ocrService.recognizeText(image.path);

        if (result['text'] == null ||
            result['text'].toString().trim().isEmpty) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No text detected in the image. Please ensure the certificate is clearly visible.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        // Extract certificate data using enhanced service
        final dataExtractionService = DataExtractionService();
        final extractedData = dataExtractionService.extractCertificateData(
          result['text'],
        );

        // Close loading
        Navigator.pop(context);

        // Update certificate data
        setState(() {
          final index = _expiryCertificates.indexWhere(
            (cert) => cert['id'] == certificateId,
          );
          if (index != -1) {
            if (extractedData['certificateType'] != null &&
                extractedData['certificateType'].toString().isNotEmpty) {
              _expiryCertificates[index]['certificateType'] =
                  extractedData['certificateType'];
            }
            if (extractedData['dateIssued'] != null &&
                extractedData['dateIssued'].toString().isNotEmpty) {
              _expiryCertificates[index]['dateIssued'] =
                  extractedData['dateIssued'];
            }
            if (extractedData['dateExpiry'] != null &&
                extractedData['dateExpiry'].toString().isNotEmpty) {
              _expiryCertificates[index]['dateExpiry'] =
                  extractedData['dateExpiry'];
            }
            _expiryFiles[certificateId.toString()] = image.path;
          }
        });

        // Show success message with extracted fields
        final extractedFields = <String>[];
        if (extractedData['certificateType'] != null)
          extractedFields.add('Type: ${extractedData['certificateType']}');
        if (extractedData['dateIssued'] != null)
          extractedFields.add('Issued: ${extractedData['dateIssued']}');
        if (extractedData['dateExpiry'] != null)
          extractedFields.add('Expires: ${extractedData['dateExpiry']}');

        final message = extractedFields.isNotEmpty
            ? 'Certificate scanned successfully!\n\n${extractedFields.join('\n')}\n\nPlease review and complete the form if needed.'
            : 'Certificate scanned. Please review and complete the form manually.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      } catch (e) {
        Navigator.pop(context); // Close loading if open
        throw e;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to scan certificate: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildExpiryBox(String label, String value) {
    return Container(
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _viewFileForMember(String department, dynamic id) {
    String? fileName;
    if (department == 'deck') {
      fileName = _deckFiles[id.toString()];
    } else if (department == 'engine') {
      fileName = _engineFiles[id.toString()];
    } else if (department == 'noexpiry') {
      fileName = _noExpiryFiles[id.toString()];
    } else if (department == 'expiry') {
      fileName = _expiryFiles[id.toString()];
    } else if (department == 'crew') {
      fileName = _crewFiles[id.toString()];
    } else if (department == 'sirb') {
      fileName = _sirbFiles[id.toString()];
    } else if (department == 'competency') {
      fileName = _competencyFiles[id.toString()];
    } else if (department == 'license') {
      fileName = _licenseFiles[id.toString()];
    }

    if (fileName != null && fileName.isNotEmpty) {
      final filePath = fileName;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('View File'),
          content: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('File: ${filePath.split('/').last}'),
                SizedBox(height: 16),
                Image.file(File(filePath), height: 300, fit: BoxFit.contain),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  void _deleteFileForMember(String department, dynamic id) {
    setState(() {
      if (department == 'deck') {
        _deckFiles.remove(id.toString());
      } else if (department == 'engine') {
        _engineFiles.remove(id.toString());
      } else if (department == 'noexpiry') {
        _noExpiryFiles.remove(id.toString());
      } else if (department == 'expiry') {
        _expiryFiles.remove(id.toString());
      } else if (department == 'crew') {
        _crewFiles.remove(id.toString());
      } else if (department == 'sirb') {
        _sirbFiles.remove(id.toString());
      } else if (department == 'competency') {
        _competencyFiles.remove(id.toString());
      } else if (department == 'license') {
        _licenseFiles.remove(id.toString());
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('File deleted'), backgroundColor: Colors.orange),
    );
  }

  // Common helper methods for Step 5 tables
  void _selectExpiryDate(String tableType, int id) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        final dateStr = '${picked.day}/${picked.month}/${picked.year}';
        if (tableType == 'sirb') {
          _updateSirbMember(id, 'dateExpiry', dateStr);
        } else if (tableType == 'competency') {
          _updateCompetencyCertificate(id, 'dateExpiry', dateStr);
        } else if (tableType == 'license') {
          _updateCompetencyLicense(id, 'dateExpiry', dateStr);
        }
      });
    }
  }

  void _uploadFile(String tableType, int id) async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select File Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        if (tableType == 'sirb') {
          _sirbFiles[id.toString()] = image.path;
        } else if (tableType == 'competency') {
          _competencyFiles[id.toString()] = image.path;
        } else if (tableType == 'license') {
          _licenseFiles[id.toString()] = image.path;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File uploaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload file'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _scanCertificate(String tableType, int id) async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Scan Certificate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Scanning certificate...'),
            ],
          ),
        ),
      );

      try {
        final result = await _ocrService.recognizeText(image.path);

        if (result['text'] == null ||
            result['text'].toString().trim().isEmpty) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No text detected in the image. Please ensure the certificate is clearly visible.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        final dataExtractionService = DataExtractionService();
        Map<String, dynamic> extractedData;

        if (tableType == 'competency') {
          extractedData = dataExtractionService.extractCOCData(result['text']);
        } else {
          extractedData = dataExtractionService.extractCrewData(result['text']);
        }

        Navigator.pop(context);

        setState(() {
          if (tableType == 'sirb') {
            if (extractedData['name'] != null &&
                extractedData['name'].toString().isNotEmpty) {
              _updateSirbMember(id, 'name', extractedData['name']);
            }
            if (extractedData['position'] != null &&
                extractedData['position'].toString().isNotEmpty) {
              _updateSirbMember(id, 'position', extractedData['position']);
            }
            if (extractedData['expiryDate'] != null &&
                extractedData['expiryDate'].toString().isNotEmpty) {
              final dateStr = extractedData['expiryDate'].toString();
              if (dateStr.contains('-')) {
                final parts = dateStr.split('-');
                _updateSirbMember(
                  id,
                  'dateExpiry',
                  '${parts[2]}/${parts[1]}/${parts[0]}',
                );
              } else {
                _updateSirbMember(id, 'dateExpiry', dateStr);
              }
            }
            _sirbFiles[id.toString()] = image.path;
          } else if (tableType == 'competency') {
            if (extractedData['name'] != null &&
                extractedData['name'].toString().isNotEmpty) {
              _updateCompetencyCertificate(id, 'name', extractedData['name']);
            }
            if (extractedData['position'] != null &&
                extractedData['position'].toString().isNotEmpty) {
              _updateCompetencyCertificate(
                id,
                'position',
                extractedData['position'],
              );
            }
            if (extractedData['expiryDate'] != null &&
                extractedData['expiryDate'].toString().isNotEmpty) {
              final dateStr = extractedData['expiryDate'].toString();
              if (dateStr.contains('-')) {
                final parts = dateStr.split('-');
                _updateCompetencyCertificate(
                  id,
                  'dateExpiry',
                  '${parts[2]}/${parts[1]}/${parts[0]}',
                );
              } else {
                _updateCompetencyCertificate(id, 'dateExpiry', dateStr);
              }
            }
            _competencyFiles[id.toString()] = image.path;
          } else if (tableType == 'license') {
            if (extractedData['name'] != null &&
                extractedData['name'].toString().isNotEmpty) {
              _updateCompetencyLicense(id, 'name', extractedData['name']);
            }
            if (extractedData['licenseType'] != null &&
                extractedData['licenseType'].toString().isNotEmpty) {
              _updateCompetencyLicense(
                id,
                'licenseType',
                extractedData['licenseType'],
              );
            } else if (extractedData['certificateType'] != null &&
                extractedData['certificateType'].toString().isNotEmpty) {
              _updateCompetencyLicense(
                id,
                'licenseType',
                extractedData['certificateType'],
              );
            }
            if (extractedData['expiryDate'] != null &&
                extractedData['expiryDate'].toString().isNotEmpty) {
              final dateStr = extractedData['expiryDate'].toString();
              if (dateStr.contains('-')) {
                final parts = dateStr.split('-');
                _updateCompetencyLicense(
                  id,
                  'dateExpiry',
                  '${parts[2]}/${parts[1]}/${parts[0]}',
                );
              } else {
                _updateCompetencyLicense(id, 'dateExpiry', dateStr);
              }
            }
            _licenseFiles[id.toString()] = image.path;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Certificate scanned successfully! Please review and complete the form if needed.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } catch (e) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to scan certificate: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to scan certificate: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  int get _calculatePsscTotal {
    final authorizedCrew = int.tryParse(_authorizedCrewController.text) ?? 0;
    final others = int.tryParse(_othersNumberController.text) ?? 0;
    return authorizedCrew + others;
  }

  void _onCompanySelected(String? companyName) {
    final newValue = companyName ?? '';
    if (_selectedCompanyOwner != newValue) {
      setState(() {
        _selectedCompanyOwner = newValue;
        // Auto-fill shipping code based on selected company using cached map
        if (companyName != null && companyName.isNotEmpty) {
          final code = _companyNameToCode[companyName];
          if (code != null && code.isNotEmpty) {
            _shippingCodeController.text = code;
          }
        } else {
          _shippingCodeController.clear();
        }
      });
      _scheduleDraftSave();
    }
  }

  void _onDraftFieldChanged() {
    if (_isEditMode || _isRestoringDraft) {
      return;
    }
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    if (_isEditMode || _isRestoringDraft) {
      return;
    }
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveDraft());
    });
  }

  bool get _isStep1DraftEmpty =>
      _selectedVesselType.isEmpty &&
      _selectedCompanyOwner.isEmpty &&
      _vesselNameController.text.trim().isEmpty &&
      _imoNumberController.text.trim().isEmpty &&
      _shippingCodeController.text.trim().isEmpty &&
      _contactNumberController.text.trim().isEmpty &&
      _masterController.text.trim().isEmpty &&
      _chiefEngineerController.text.trim().isEmpty;

  Future<void> _saveDraft() async {
    if (_isEditMode) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (_isStep1DraftEmpty) {
      await prefs.remove(_draftStorageKey);
      return;
    }

    final draftData = jsonEncode({
      'selectedVesselType': _selectedVesselType,
      'vesselName': _vesselNameController.text,
      'imoNumber': _imoNumberController.text,
      'companyOwner': _selectedCompanyOwner,
      'shippingCode': _shippingCodeController.text,
      'contactNumber': _contactNumberController.text,
      'master': _masterController.text,
      'chiefEngineer': _chiefEngineerController.text,
    });

    await prefs.setString(_draftStorageKey, draftData);
  }

  Future<void> _loadDraft() async {
    if (_isEditMode) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final storedDraft = prefs.getString(_draftStorageKey);
    if (storedDraft == null) {
      return;
    }

    _isRestoringDraft = true;
    try {
      final Map<String, dynamic> draft =
          jsonDecode(storedDraft) as Map<String, dynamic>;

      _vesselNameController.text = draft['vesselName'] as String? ?? '';
      _imoNumberController.text = draft['imoNumber'] as String? ?? '';
      _shippingCodeController.text = draft['shippingCode'] as String? ?? '';
      _contactNumberController.text =
          draft['contactNumber'] as String? ?? '';
      _masterController.text = draft['master'] as String? ?? '';
      _chiefEngineerController.text =
          draft['chiefEngineer'] as String? ?? '';

      final vesselType = draft['selectedVesselType'] as String? ?? '';
      final companyOwner = draft['companyOwner'] as String? ?? '';

      if (mounted) {
        setState(() {
          _selectedVesselType =
              _validVesselTypes.contains(vesselType) ? vesselType : '';
          _selectedCompanyOwner =
              _validCompanyNames.contains(companyOwner) ? companyOwner : '';
        });
      } else {
        _selectedVesselType =
            _validVesselTypes.contains(vesselType) ? vesselType : '';
        _selectedCompanyOwner =
            _validCompanyNames.contains(companyOwner) ? companyOwner : '';
      }

      if (_selectedCompanyOwner.isNotEmpty) {
        final mappedCode = _companyNameToCode[_selectedCompanyOwner];
        if ((draft['shippingCode'] as String? ?? '').isEmpty &&
            mappedCode != null &&
            mappedCode.isNotEmpty) {
          _shippingCodeController.text = mappedCode;
        }
      }
    } catch (error) {
      await prefs.remove(_draftStorageKey);
    } finally {
      _isRestoringDraft = false;
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftStorageKey);
  }


  // Deck Department Methods
  void _addDeckEntry(Map<String, String> newEntry) {
    if (newEntry['position']!.isEmpty ||
        newEntry['license']!.isEmpty ||
        newEntry['number']!.isEmpty)
      return;
    setState(() {
      _deckDepartment.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'position': newEntry['position']!,
        'license': newEntry['license']!,
        'number': newEntry['number']!,
      });
    });
  }

  void _deleteDeckEntry(int id) {
    setState(() {
      _deckDepartment.removeWhere((entry) => entry['id'] == id);
    });
  }

  void _updateDeckEntry(int id, String field, String value) {
    final index = _deckDepartment.indexWhere((entry) => entry['id'] == id);
    if (index != -1 && _deckDepartment[index][field] != value) {
      setState(() {
        _deckDepartment[index][field] = value;
      });
    }
  }

  // Engine Department Methods
  void _addEngineEntry(Map<String, String> newEntry) {
    if (newEntry['position']!.isEmpty ||
        newEntry['license']!.isEmpty ||
        newEntry['number']!.isEmpty)
      return;
    setState(() {
      _engineDepartment.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'position': newEntry['position']!,
        'license': newEntry['license']!,
        'number': newEntry['number']!,
      });
    });
  }

  void _deleteEngineEntry(int id) {
    setState(() {
      _engineDepartment.removeWhere((entry) => entry['id'] == id);
    });
  }

  void _updateEngineEntry(int id, String field, String value) {
    final index = _engineDepartment.indexWhere((entry) => entry['id'] == id);
    if (index != -1 && _engineDepartment[index][field] != value) {
      setState(() {
        _engineDepartment[index][field] = value;
      });
    }
  }

  void _confirmDeleteMember(String department, int id) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text('Delete Member?', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove this ${department == 'deck' ? 'deck' : 'engine'} member?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (department == 'deck') {
                  _deleteDeckEntry(id);
                } else {
                  _deleteEngineEntry(id);
                }
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Member removed successfully'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.red,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showAddMemberDialog(String department) {
    String position = '';
    String license = '';
    String number = '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'Add ${department == 'deck' ? 'Deck' : 'Engine'} Member',
              ),
              content: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Position Dropdown
                    DropdownButtonFormField<String>(
                      value: position.isEmpty || !_positions.contains(position) ? null : position,
                      decoration: InputDecoration(
                        labelText: 'Position *',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      items: _positions
                          .toSet() // Remove duplicates
                          .map(
                            (pos) =>
                                DropdownMenuItem(value: pos, child: Text(pos)),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => position = value ?? ''),
                    ),
                    const SizedBox(height: 12),
                    // License Dropdown
                    DropdownButtonFormField<String>(
                      value: license.isEmpty || !_licenses.contains(license) ? null : license,
                      decoration: InputDecoration(
                        labelText: 'License *',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      items: _licenses
                          .toSet() // Remove duplicates
                          .map(
                            (lic) =>
                                DropdownMenuItem(value: lic, child: Text(lic)),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => license = value ?? ''),
                    ),
                    const SizedBox(height: 12),
                    // Number Input
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Number *',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) => setState(() => number = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (position.isNotEmpty &&
                        license.isNotEmpty &&
                        number.isNotEmpty) {
                      if (department == 'deck') {
                        _addDeckEntry({
                          'position': position,
                          'license': license,
                          'number': number,
                        });
                      } else {
                        _addEngineEntry({
                          'position': position,
                          'license': license,
                          'number': number,
                        });
                      }
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Member added successfully'),
                          duration: Duration(seconds: 2),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createAdminNotifications({
    required Map<String, dynamic> vesselData,
    required bool isNewSubmission,
    required Map<String, dynamic>? submitterInfo,
  }) async {
    try {
      final roles = ['admin', 'super_admin'];
      final adminsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: roles)
          .get();

      if (adminsSnapshot.docs.isEmpty) {
        debugPrint('⚠️ No admin users found for notifications');
        return;
      }

      final resolvedSubmitterName = (submitterInfo?['username'] ??
              submitterInfo?['displayName'] ??
              submitterInfo?['name'] ??
              submitterInfo?['email'] ??
              'Unknown User')
          .toString();
      final submittedBy =
          (submitterInfo?['uid'] ?? submitterInfo?['id'] ?? 'unknown').toString();

      final vesselId =
          (vesselData['id'] ?? vesselData['vesselId'] ?? 'unknown').toString();
      final vesselName =
          (vesselData['vesselName'] ?? 'Unknown').toString().trim();
      final imoNumber = (vesselData['imoNumber'] ?? '').toString().trim();
      final companyOwner =
          (vesselData['companyOwner'] ?? 'Unknown').toString().trim();
      final vesselType =
          (vesselData['vesselType'] ?? 'Unknown').toString().trim();
      final timestamp = DateTime.now().toIso8601String();
      final imoSuffix = imoNumber.isNotEmpty ? ' ($imoNumber)' : '';
      final submissionVerb = isNewSubmission ? 'submitted' : 'resubmitted';
      final title =
          isNewSubmission ? 'New Vessel Submission' : 'Vessel Resubmission';
      final message =
          '$resolvedSubmitterName has $submissionVerb vessel "$vesselName"$imoSuffix for review.';

      final batch = FirebaseFirestore.instance.batch();
      int notificationsCreated = 0;

      for (final adminDoc in adminsSnapshot.docs) {
        final adminData = adminDoc.data();
        final adminUserId =
            (adminData['uid'] ?? adminDoc.id)?.toString().trim() ?? '';

        if (adminUserId.isEmpty) {
          debugPrint(
              '⚠️ Skipping admin notification - missing UID for doc ${adminDoc.id}');
          continue;
        }

        final notificationRef =
            FirebaseFirestore.instance.collection('notifications').doc();

        batch.set(notificationRef, {
          'userId': adminUserId,
          'vesselId': vesselId,
          'vesselName': vesselName.isNotEmpty ? vesselName : 'Unknown',
          'submittedBy': submittedBy,
          'submitterName': resolvedSubmitterName,
          'type': 'info',
          'title': title,
          'message': message,
          'timestamp': timestamp,
          'isRead': false,
          'priority': 'normal',
          'vesselType': vesselType.isNotEmpty ? vesselType : 'Unknown',
          'companyOwner': companyOwner.isNotEmpty ? companyOwner : 'Unknown',
          'actionType': submissionVerb,
          'navigation': {
            'type': 'vessel',
            'vesselId': vesselId,
            'mode': 'review',
            'tab': 'status',
          },
        });

        notificationsCreated += 1;
      }

      if (notificationsCreated > 0) {
        await batch.commit();
        debugPrint(
            '✅ Created $notificationsCreated admin notification(s) for vessel "$vesselName"');
      } else {
        debugPrint('⚠️ No admin notifications queued for batch commit');
      }
    } catch (error, stackTrace) {
      debugPrint(
          '❌ Error creating admin notifications: $error\n$stackTrace');
      // Don't rethrow to avoid blocking vessel submission
    }
  }

  Future<void> _submitForm() async {
    if (_isSubmitting) return;

    // Validate steps 4 and 5 only for add mode
    if (!_isEditMode) {
      final step4Complete = await _validateStep4();
      if (!step4Complete) {
        return;
      }

      final step5Complete = await _validateStep5();
      if (!step5Complete) {
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?['uid'];

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Check for duplicate IMO only when not in edit mode
      if (!_isEditMode) {
        final existingVessels = await FirebaseFirestore.instance
            .collection('vessels')
            .where('imoNumber', isEqualTo: _imoNumberController.text.trim())
            .get();

        if (existingVessels.docs.isNotEmpty) {
          _showErrorDialog(
            'Vessel Already Exists',
            'A vessel with official number ${_imoNumberController.text.trim()} already exists.',
          );
          return;
        }
      }

      // Get existing data for edit mode
      final data = _isEditMode && widget.vesselData != null
          ? widget.vesselData!
          : {};

      // Show progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Uploading files to Cloudinary...'),
              ],
            ),
          ),
        );
      }

      // Create vessel document first to get vesselId
      final vesselData = {
        // Step 1: Vessel Information
        'vesselName': _vesselNameController.text.trim(),
        'imoNumber': _imoNumberController.text.trim(),
        'vesselType': _selectedVesselType,
        'companyOwner': _selectedCompanyOwner,
        'shippingCode': _shippingCodeController.text.trim(),
        'contactNumber': _contactNumberController.text.trim(),
        'master': _masterController.text.trim(),
        'chiefEngineer': _chiefEngineerController.text.trim(),

        // Step 2: General Particulars
        'typeOfShip': _typeOfShipController.text.trim(),
        'grossTonnage': _grossTonnageController.text.trim(),
        'netTonnage': _netTonnageController.text.trim(),
        'placeBuilt': _placeBuiltController.text.trim(),
        'yearBuilt': _yearBuiltController.text.trim(),
        'builder': _builderController.text.trim(),
        'length': _lengthController.text.trim(),
        'homeport': _homeportController.text.trim(),
        'hullMaterial': _selectedHullMaterial,
        'numberOfEngines': _numberOfEnginesController.text.trim(),
        'kilowatt': _kilowattController.text.trim(),

        // Step 3: Manning Requirements
        'deckDepartment': _deckDepartment,
        'engineDepartment': _engineDepartment,
        'authorizedCrew': _authorizedCrewController.text.trim(),
        'othersNumber': _othersNumberController.text.trim(),

        // Store both userId (web standard) and clientId (mobile backward compatibility)
        'userId': userId,
        'clientId': userId,
        'createdAt': _isEditMode
            ? (widget.vesselData!['createdAt'] ??
                  DateTime.now().toIso8601String())
            : DateTime.now().toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
        'submissionStatus': _isEditMode
            ? (widget.vesselData!['submissionStatus'] ?? 'pending')
            : 'pending',
        'submittedAt': _isEditMode
            ? (widget.vesselData!['submittedAt'] ??
                  DateTime.now().toIso8601String())
            : DateTime.now().toIso8601String(),
        'certificates': [],
        'expiryCertificates': [],
        'competencyCertificates': [],
        'competencyLicenses': [],
        'officersCrew': [],
        'status': 'active',
      };

      // noExpiryDocs will be added later after processing files

      // Create or update vessel document
      DocumentReference vesselRef;
      String vesselId;

      if (_isEditMode && widget.vesselId != null) {
        // Update existing vessel
        vesselId = widget.vesselId!;
        vesselRef =
            FirebaseFirestore.instance.collection('vessels').doc(vesselId);
        await vesselRef.update(vesselData);

        final previousStatus = (widget.vesselData?['submissionStatus'] ?? '')
            .toString()
            .toLowerCase();
        final currentStatus =
            (vesselData['submissionStatus'] ?? '').toString().toLowerCase();
        if (previousStatus == 'declined' &&
            currentStatus == 'pending' &&
            authProvider.user != null) {
          await _createAdminNotifications(
            vesselData: {...vesselData, 'id': vesselId},
            isNewSubmission: false,
            submitterInfo: authProvider.user,
          );
        }
      } else {
        // Create new vessel
        vesselRef = await FirebaseFirestore.instance
            .collection('vessels')
            .add(vesselData);
        vesselId = vesselRef.id;

        await _createAdminNotifications(
          vesselData: {...vesselData, 'id': vesselId},
          isNewSubmission: true,
          submitterInfo: authProvider.user,
        );
      }

      // Upload files to Cloudinary and update certificates
      try {
        // Process NO EXPIRY certificates (Certificate of Philippine Registry, Certificate of Ownership, Tonnage Measurement)
        List<Map<String, dynamic>> processedNoExpiryDocs = [];

        // Certificate of Philippine Registry
        final philippineRegistryDate = _philippineRegistryDateController.text
            .trim();
        if (philippineRegistryDate.isNotEmpty) {
          final filePath = _noExpiryFiles['philippineRegistry'];
          String? fileUrl;

          // Upload file if exists
          if (filePath != null && File(filePath).existsSync()) {
            try {
              fileUrl = await CloudinaryService.uploadCertificate(
                file: File(filePath),
                vesselId: vesselId,
                certificateId: 'philippineRegistry',
              );
            } catch (e) {
              print('Failed to upload Philippine Registry file: $e');
              // Check for existing file URL when editing
              if (_isEditMode && widget.vesselData != null) {
                final existingNoExpiryDocs =
                    widget.vesselData!['noExpiryDocs'] as List? ?? [];
                final existingDocs = existingNoExpiryDocs
                    .where(
                      (doc) =>
                          doc['certificateType'] ==
                          'CERTIFICATE OF PHILIPPINE REGISTRY',
                    )
                    .toList();
                if (existingDocs.isNotEmpty) {
                  final existingDoc = existingDocs.first;
                  if (existingDoc['url'] != null) {
                    fileUrl = existingDoc['url'];
                  } else if (existingDoc['certificateFileUrl'] != null) {
                    fileUrl = existingDoc['certificateFileUrl'];
                  }
                }
              }
            }
          } else if (_isEditMode && widget.vesselData != null) {
            // Keep existing file URL when not uploading new file
            final existingNoExpiryDocs =
                widget.vesselData!['noExpiryDocs'] as List? ?? [];
            final existingDocs = existingNoExpiryDocs
                .where(
                  (doc) =>
                      doc['certificateType'] ==
                      'CERTIFICATE OF PHILIPPINE REGISTRY',
                )
                .toList();
            if (existingDocs.isNotEmpty) {
              final existingDoc = existingDocs.first;
              if (existingDoc['url'] != null) {
                fileUrl = existingDoc['url'];
              } else if (existingDoc['certificateFileUrl'] != null) {
                fileUrl = existingDoc['certificateFileUrl'];
              }
            }
          }

          processedNoExpiryDocs.add({
            'id': DateTime.now().millisecondsSinceEpoch,
            'certificateType': 'CERTIFICATE OF PHILIPPINE REGISTRY',
            'dateIssued': philippineRegistryDate,
            'dateExpiry': null,
            'status': 'VALID',
            'remarks': 'VALID',
            if (fileUrl != null) ...{
              'url': fileUrl,
              'downloadURL': fileUrl,
              'fileUrl': fileUrl,
              'certificateFileUrl': fileUrl,
              'cloudinaryUrl': fileUrl,
              'documentUrl': fileUrl,
            },
            'uploadDate': DateTime.now().toIso8601String(),
          });
        }

        // Certificate of Ownership
        final ownershipDate = _ownershipDateController.text.trim();
        if (ownershipDate.isNotEmpty) {
          final filePath = _noExpiryFiles['ownership'];
          String? fileUrl;

          // Upload file if exists
          if (filePath != null && File(filePath).existsSync()) {
            try {
              fileUrl = await CloudinaryService.uploadCertificate(
                file: File(filePath),
                vesselId: vesselId,
                certificateId: 'ownership',
              );
            } catch (e) {
              print('Failed to upload Ownership file: $e');
              // Check for existing file URL when editing
              if (_isEditMode && widget.vesselData != null) {
                final existingNoExpiryDocs =
                    widget.vesselData!['noExpiryDocs'] as List? ?? [];
                final existingDocs = existingNoExpiryDocs
                    .where(
                      (doc) =>
                          doc['certificateType'] == 'CERTIFICATE OF OWNERSHIP',
                    )
                    .toList();
                if (existingDocs.isNotEmpty) {
                  final existingDoc = existingDocs.first;
                  if (existingDoc['url'] != null) {
                    fileUrl = existingDoc['url'];
                  } else if (existingDoc['certificateFileUrl'] != null) {
                    fileUrl = existingDoc['certificateFileUrl'];
                  }
                }
              }
            }
          } else if (_isEditMode && widget.vesselData != null) {
            // Keep existing file URL when not uploading new file
            final existingNoExpiryDocs =
                widget.vesselData!['noExpiryDocs'] as List? ?? [];
            final existingDocs = existingNoExpiryDocs
                .where(
                  (doc) => doc['certificateType'] == 'CERTIFICATE OF OWNERSHIP',
                )
                .toList();
            if (existingDocs.isNotEmpty) {
              final existingDoc = existingDocs.first;
              if (existingDoc['url'] != null) {
                fileUrl = existingDoc['url'];
              } else if (existingDoc['certificateFileUrl'] != null) {
                fileUrl = existingDoc['certificateFileUrl'];
              }
            }
          }

          processedNoExpiryDocs.add({
            'id': DateTime.now().millisecondsSinceEpoch + 1,
            'certificateType': 'CERTIFICATE OF OWNERSHIP',
            'dateIssued': ownershipDate,
            'dateExpiry': null,
            'status': 'VALID',
            'remarks': 'VALID',
            if (fileUrl != null) ...{
              'url': fileUrl,
              'downloadURL': fileUrl,
              'fileUrl': fileUrl,
              'certificateFileUrl': fileUrl,
              'cloudinaryUrl': fileUrl,
              'documentUrl': fileUrl,
            },
            'uploadDate': DateTime.now().toIso8601String(),
          });
        }

        // Tonnage Measurement
        final tonnageDate = _tonnageDateController.text.trim();
        if (tonnageDate.isNotEmpty) {
          final filePath = _noExpiryFiles['tonnage'];
          String? fileUrl;

          // Upload file if exists
          if (filePath != null && File(filePath).existsSync()) {
            try {
              fileUrl = await CloudinaryService.uploadCertificate(
                file: File(filePath),
                vesselId: vesselId,
                certificateId: 'tonnage',
              );
            } catch (e) {
              print('Failed to upload Tonnage Measurement file: $e');
              // Check for existing file URL when editing
              if (_isEditMode && widget.vesselData != null) {
                final existingNoExpiryDocs =
                    widget.vesselData!['noExpiryDocs'] as List? ?? [];
                final existingDocs = existingNoExpiryDocs
                    .where(
                      (doc) => doc['certificateType'] == 'TONNAGE MEASUREMENT',
                    )
                    .toList();
                if (existingDocs.isNotEmpty) {
                  final existingDoc = existingDocs.first;
                  if (existingDoc['url'] != null) {
                    fileUrl = existingDoc['url'];
                  } else if (existingDoc['certificateFileUrl'] != null) {
                    fileUrl = existingDoc['certificateFileUrl'];
                  }
                }
              }
            }
          } else if (_isEditMode && widget.vesselData != null) {
            // Keep existing file URL when not uploading new file
            final existingNoExpiryDocs =
                widget.vesselData!['noExpiryDocs'] as List? ?? [];
            final existingDocs = existingNoExpiryDocs
                .where((doc) => doc['certificateType'] == 'TONNAGE MEASUREMENT')
                .toList();
            if (existingDocs.isNotEmpty) {
              final existingDoc = existingDocs.first;
              if (existingDoc['url'] != null) {
                fileUrl = existingDoc['url'];
              } else if (existingDoc['certificateFileUrl'] != null) {
                fileUrl = existingDoc['certificateFileUrl'];
              }
            }
          }

          processedNoExpiryDocs.add({
            'id': DateTime.now().millisecondsSinceEpoch + 2,
            'certificateType': 'TONNAGE MEASUREMENT',
            'dateIssued': tonnageDate,
            'dateExpiry': null,
            'status': 'VALID',
            'remarks': 'VALID',
            if (fileUrl != null) ...{
              'url': fileUrl,
              'downloadURL': fileUrl,
              'fileUrl': fileUrl,
              'certificateFileUrl': fileUrl,
              'cloudinaryUrl': fileUrl,
              'documentUrl': fileUrl,
            },
            'uploadDate': DateTime.now().toIso8601String(),
          });
        }

        // Process expiry certificates with files
        List<Map<String, dynamic>> processedExpiryCerts = [];
        for (var cert in _expiryCertificates) {
          final certId = cert['id'].toString();
          final filePath = _expiryFiles[certId];

          Map<String, dynamic> processedCert = Map<String, dynamic>.from(cert);

          // Keep existing file URL if not uploading new file
          if (filePath != null && File(filePath).existsSync()) {
            try {
              final fileUrl = await CloudinaryService.uploadCertificate(
                file: File(filePath),
                vesselId: vesselId,
                certificateId: certId,
              );
              processedCert['certificateFileUrl'] = fileUrl;
              processedCert['fileUrl'] = fileUrl;
            } catch (e) {
              print('Failed to upload certificate file: $e');
              // Continue without file URL - use existing if available
              if (_isEditMode && cert['certificateFileUrl'] != null) {
                processedCert['certificateFileUrl'] =
                    cert['certificateFileUrl'];
              }
            }
          } else if (_isEditMode && cert['certificateFileUrl'] != null) {
            // Keep existing file URL when not uploading new file
            processedCert['certificateFileUrl'] = cert['certificateFileUrl'];
          }

          // Remove internal id field before saving
          processedCert.remove('id');
          processedExpiryCerts.add(processedCert);
        }

        // Process competency certificates with files
        List<Map<String, dynamic>> processedCompetencyCerts = [];
        for (var cert in _competencyCertificates) {
          final certId = cert['id'].toString();
          final filePath = _competencyFiles[certId];

          Map<String, dynamic> processedCert = Map<String, dynamic>.from(cert);

          if (filePath != null && File(filePath).existsSync()) {
            try {
              final fileUrl = await CloudinaryService.uploadCertificate(
                file: File(filePath),
                vesselId: vesselId,
                certificateId: certId,
              );
              processedCert['certificateFileUrl'] = fileUrl;
              processedCert['fileUrl'] = fileUrl;
            } catch (e) {
              print('Failed to upload competency certificate file: $e');
              if (_isEditMode && cert['certificateFileUrl'] != null) {
                processedCert['certificateFileUrl'] =
                    cert['certificateFileUrl'];
              }
            }
          } else if (_isEditMode && cert['certificateFileUrl'] != null) {
            processedCert['certificateFileUrl'] = cert['certificateFileUrl'];
          }

          processedCert.remove('id');
          processedCompetencyCerts.add(processedCert);
        }

        // Process competency licenses with files
        List<Map<String, dynamic>> processedLicenses = [];
        for (var license in _competencyLicenses) {
          final licenseId = license['id'].toString();
          final filePath = _licenseFiles[licenseId];

          Map<String, dynamic> processedLicense = Map<String, dynamic>.from(
            license,
          );

          if (filePath != null && File(filePath).existsSync()) {
            try {
              final fileUrl = await CloudinaryService.uploadCertificate(
                file: File(filePath),
                vesselId: vesselId,
                certificateId: licenseId,
              );
              processedLicense['certificateFileUrl'] = fileUrl;
              processedLicense['fileUrl'] = fileUrl;
            } catch (e) {
              print('Failed to upload license file: $e');
              if (_isEditMode && license['certificateFileUrl'] != null) {
                processedLicense['certificateFileUrl'] =
                    license['certificateFileUrl'];
              }
            }
          } else if (_isEditMode && license['certificateFileUrl'] != null) {
            processedLicense['certificateFileUrl'] =
                license['certificateFileUrl'];
          }

          processedLicense.remove('id');
          processedLicenses.add(processedLicense);
        }

        // Combine officersCrew (SIRB members)
        List<Map<String, dynamic>> officersCrew = [];
        for (var member in _sirbMembers) {
          final memberId = member['id'].toString();
          final filePath = _sirbFiles[memberId];

          Map<String, dynamic> processedMember = Map<String, dynamic>.from(
            member,
          );

          if (filePath != null && File(filePath).existsSync()) {
            try {
              final fileUrl = await CloudinaryService.uploadScannedFile(
                file: File(filePath),
                vesselId: vesselId,
                documentType: 'sirb',
              );
              processedMember['fileUrl'] = fileUrl;
            } catch (e) {
              print('Failed to upload SIRB file: $e');
              if (_isEditMode && member['fileUrl'] != null) {
                processedMember['fileUrl'] = member['fileUrl'];
              }
            }
          } else if (_isEditMode && member['fileUrl'] != null) {
            processedMember['fileUrl'] = member['fileUrl'];
          }

          processedMember.remove('id');
          officersCrew.add(processedMember);
        }

        // Update vessel document with all certificates and crew
        final updateData = {
          'noExpiryDocs': processedNoExpiryDocs,
          'expiryCertificates': processedExpiryCerts,
          'competencyCertificates': processedCompetencyCerts,
          'competencyLicenses': processedLicenses,
          'officersCrew': officersCrew,
          'lastUpdated': DateTime.now().toIso8601String(),
        };

        // Preserve certificate arrays if editing and they exist
        if (_isEditMode && widget.vesselData != null) {
          // Keep existing certificate URLs if no new file was uploaded
          if (processedNoExpiryDocs.isEmpty &&
              widget.vesselData!['noExpiryDocs'] != null) {
            updateData['noExpiryDocs'] = widget.vesselData!['noExpiryDocs'];
          }
          if (processedExpiryCerts.isEmpty &&
              widget.vesselData!['expiryCertificates'] != null) {
            updateData['expiryCertificates'] =
                widget.vesselData!['expiryCertificates'];
          }
          if (processedCompetencyCerts.isEmpty &&
              widget.vesselData!['competencyCertificates'] != null) {
            updateData['competencyCertificates'] =
                widget.vesselData!['competencyCertificates'];
          }
          if (processedLicenses.isEmpty &&
              widget.vesselData!['competencyLicenses'] != null) {
            updateData['competencyLicenses'] =
                widget.vesselData!['competencyLicenses'];
          }
          if (officersCrew.isEmpty &&
              widget.vesselData!['officersCrew'] != null) {
            updateData['officersCrew'] = widget.vesselData!['officersCrew'];
          }
        }

        await vesselRef.update(updateData);

        // Close progress dialog
        if (mounted) {
          Navigator.of(context).pop(); // Close progress dialog
        }
      } catch (uploadError) {
        print('Error uploading files: $uploadError');
        // Close progress dialog if still open
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        // Vessel was created, but files failed to upload
        // Still show success but warn about files
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Vessel added, but some files failed to upload. Please update later.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      if (mounted) {
        _shouldPersistDraftOnDispose = false;
        await _clearDraft();
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        final vesselName = _vesselNameController.text.trim();

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _isEditMode
                  ? 'Vessel updated successfully!'
                  : 'Vessel added successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );

        if (_isEditMode) {
          navigator.pop();
        } else {
          final shouldViewStatus =
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => VesselSubmissionSuccessDialog(
                  vesselName: vesselName.isEmpty ? null : vesselName,
                  onViewStatus: () => Navigator.of(dialogContext).pop(true),
                ),
              ) ??
              false;

          if (!mounted) {
            return;
          }

          if (shouldViewStatus) {
            navigator.pushReplacement(
              MaterialPageRoute(
                builder: (_) => ApprovalStatusScreen(
                  vesselName: vesselName.isEmpty ? null : vesselName,
                ),
              ),
            );
          } else {
            navigator.pop();
          }
        }
      }
    } catch (error) {
      print('Error ${_isEditMode ? 'updating' : 'adding'} vessel: $error');
      // Close progress dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
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
    // Show loading overlay when loading data in edit mode
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isEditMode ? 'Edit Vessel' : 'Add Vessel'),
          backgroundColor: const Color(0xFF0A4D68),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading vessel data...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditMode
              ? 'Edit Vessel - Step ${_currentStep + 1} of 3'
              : 'Add Vessel - Step ${_currentStep + 1} of 5',
        ),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _continue,
        onStepCancel: _cancel,
        onStepTapped: _onStepTapped,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                if (_currentStep > 0)
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
                const SizedBox(width: 12),
                if ((_isEditMode && _currentStep < 2) ||
                    (!_isEditMode && _currentStep < 4))
                  ElevatedButton(
                    onPressed: details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A4D68),
                    ),
                    child: const Text('Next'),
                  )
                else
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A4D68),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit'),
                  ),
              ],
            ),
          );
        },
        steps: [
          _buildStep1(),
          _buildStep2(),
          _buildStep3(),
          if (!_isEditMode) ...[_buildStep4(), _buildStep5()],
        ],
      ),
    );
  }

  Step _buildStep1() {
    return Step(
      title: const Text('Vessel Information'),
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      content: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            // Vessel Type - Using cached items for better performance
            DropdownButtonFormField<String>(
              value:
                  (_selectedVesselType.isEmpty ||
                      !_validVesselTypes.contains(_selectedVesselType))
                  ? null
                  : _selectedVesselType,
              decoration: InputDecoration(
                labelText: 'Type of Vessel *',
                prefixIcon: const Icon(Icons.category),
                border: const OutlineInputBorder(),
                errorText: _vesselTypeError,
                isDense: true,
              ),
              isExpanded: true,
              items: _vesselTypeItems,
              onChanged: (value) {
                final newValue = value ?? '';
                if (_selectedVesselType != newValue) {
                  setState(() => _selectedVesselType = newValue);
                  _scheduleDraftSave();
                }
              },
            ),
            const SizedBox(height: 16),
            // Vessel Name - Auto uppercase
            TextFormField(
              controller: _vesselNameController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Vessel Name *',
                prefixIcon: const Icon(Icons.sailing),
                border: const OutlineInputBorder(),
                errorText: _vesselNameError,
              ),
            ),
            const SizedBox(height: 16),
            // Official Number - Numbers only
            TextFormField(
              controller: _imoNumberController,
              decoration: InputDecoration(
                labelText: 'Official Number *',
                prefixIcon: const Icon(Icons.tag),
                border: const OutlineInputBorder(),
                errorText: _imoError,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            const SizedBox(height: 16),
            // Company/Owner - Using cached items for better performance
            DropdownButtonFormField<String>(
              value:
                  _selectedCompanyOwner.isEmpty ||
                      !_validCompanyNames.contains(_selectedCompanyOwner)
                  ? null
                  : _selectedCompanyOwner,
              decoration: InputDecoration(
                labelText: 'Company/Owner *',
                prefixIcon: const Icon(Icons.business),
                border: const OutlineInputBorder(),
                errorText: _companyError,
                isDense: true,
              ),
              isExpanded: true,
              items: _companyItems,
              onChanged: _onCompanySelected,
            ),
            const SizedBox(height: 16),
            // Shipping Code - Auto-filled
            TextFormField(
              controller: _shippingCodeController,
              decoration: InputDecoration(
                labelText: 'Shipping Code *',
                prefixIcon: const Icon(Icons.code),
                border: const OutlineInputBorder(),
                helperText: 'Auto-filled when company is selected',
                errorText: _shippingCodeError,
                enabled: false, // Disabled since it's auto-filled
              ),
            ),
            const SizedBox(height: 16),
            // Contact Number - Max 11 digits
            TextFormField(
              controller: _contactNumberController,
              decoration: InputDecoration(
                labelText: 'Contact Number *',
                prefixIcon: const Icon(Icons.phone),
                border: const OutlineInputBorder(),
                helperText: '+63 9XX XXX XXXX or 09XX XXX XXXX (11 digits)',
                errorText: _contactNumberError,
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              onChanged: (_) {
                _validateContactNumberDebounced();
                _scheduleDraftSave();
              },
            ),
            const SizedBox(height: 16),
            // Master - Auto uppercase
            TextFormField(
              controller: _masterController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Master *',
                prefixIcon: const Icon(Icons.person),
                border: const OutlineInputBorder(),
                errorText: _masterError,
              ),
            ),
            const SizedBox(height: 16),
            // Chief Engineer - Auto uppercase
            TextFormField(
              controller: _chiefEngineerController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Chief Engineer *',
                prefixIcon: const Icon(Icons.engineering),
                border: const OutlineInputBorder(),
                errorText: _chiefEngineerError,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Step _buildStep2() {
    return Step(
      title: const Text('General Particulars'),
      isActive: _currentStep >= 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      content: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            // Type of Ship - Auto uppercase with default
            TextFormField(
              controller: _typeOfShipController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Type of Ship *',
                prefixIcon: const Icon(Icons.category),
                border: const OutlineInputBorder(),
                errorText: _typeOfShipError,
              ),
            ),
            const SizedBox(height: 16),
            // Gross Tonnage
            TextFormField(
              controller: _grossTonnageController,
              decoration: InputDecoration(
                labelText: 'Gross Tonnage *',
                prefixIcon: const Icon(Icons.format_size),
                border: const OutlineInputBorder(),
                errorText: _grossTonnageError,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            const SizedBox(height: 16),
            // Net Tonnage
            TextFormField(
              controller: _netTonnageController,
              decoration: InputDecoration(
                labelText: 'Net Tonnage *',
                prefixIcon: const Icon(Icons.format_size),
                border: const OutlineInputBorder(),
                errorText: _netTonnageError,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            const SizedBox(height: 16),
            // Place Built - Auto uppercase
            TextFormField(
              controller: _placeBuiltController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Place Built *',
                prefixIcon: const Icon(Icons.location_city),
                border: const OutlineInputBorder(),
                errorText: _placeBuiltError,
              ),
            ),
            const SizedBox(height: 16),
            // Year Built - Manual input
            TextFormField(
              controller: _yearBuiltController,
              decoration: InputDecoration(
                labelText: 'Year Built *',
                prefixIcon: const Icon(Icons.calendar_today),
                border: const OutlineInputBorder(),
                errorText: _yearBuiltError,
                helperText: 'Enter year (1970 to present)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
            ),
            const SizedBox(height: 16),
            // Builder - Auto uppercase
            TextFormField(
              controller: _builderController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Builder *',
                prefixIcon: const Icon(Icons.build),
                border: const OutlineInputBorder(),
                errorText: _builderError,
              ),
            ),
            const SizedBox(height: 16),
            // Length
            TextFormField(
              controller: _lengthController,
              decoration: InputDecoration(
                labelText: 'Length (meters) *',
                prefixIcon: const Icon(Icons.straighten),
                border: const OutlineInputBorder(),
                errorText: _lengthError,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            const SizedBox(height: 16),
            // Homeport - Auto uppercase
            TextFormField(
              controller: _homeportController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Homeport *',
                prefixIcon: const Icon(Icons.home),
                border: const OutlineInputBorder(),
                errorText: _homeportError,
              ),
            ),
            const SizedBox(height: 16),
            // Hull Material - Using cached items for better performance
            DropdownButtonFormField<String>(
              value:
                  (_selectedHullMaterial.isEmpty ||
                      !_validHullMaterials.contains(_selectedHullMaterial))
                  ? null
                  : _selectedHullMaterial,
              decoration: InputDecoration(
                labelText: 'Hull Material *',
                prefixIcon: const Icon(Icons.construction),
                border: const OutlineInputBorder(),
                errorText: _hullMaterialError,
                isDense: true,
              ),
              isExpanded: true,
              items: _hullMaterialItems,
              onChanged: (value) {
                final newValue = value ?? '';
                if (_selectedHullMaterial != newValue) {
                  setState(() => _selectedHullMaterial = newValue);
                }
              },
            ),
            const SizedBox(height: 16),
            // Number of Engines
            TextFormField(
              controller: _numberOfEnginesController,
              decoration: InputDecoration(
                labelText: 'Number of Engines *',
                prefixIcon: const Icon(Icons.settings),
                border: const OutlineInputBorder(),
                errorText: _numberOfEnginesError,
                helperText: 'Must be at least 1',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            // Kilowatt
            TextFormField(
              controller: _kilowattController,
              decoration: InputDecoration(
                labelText: 'Kilowatt *',
                prefixIcon: const Icon(Icons.flash_on),
                border: const OutlineInputBorder(),
                errorText: _kilowattError,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Step _buildStep3() {
    if (_currentStep == 2 && _shouldLaunchManningEditor) {
      _shouldLaunchManningEditor = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openManningRequirementsEditor();
        }
      });
    }

    return Step(
      title: const Text('Manning Requirements'),
      isActive: _currentStep >= 2,
      state: StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildManningSummaryCard(
            title: 'Deck Department',
            entries: _deckDepartment,
            accentColor: const Color(0xFF153E90),
          ),
          const SizedBox(height: 16),
          _buildManningSummaryCard(
            title: 'Engine Department',
            entries: _engineDepartment,
            accentColor: const Color(0xFF1F2D3D),
          ),
          const SizedBox(height: 16),
          _buildPsscSummaryCard(),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _openManningRequirementsEditor,
            icon: const Icon(Icons.table_rows_rounded),
            label: const Text('Open Manning Requirements Form'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openManningRequirementsEditor() async {
    final result = await Navigator.of(context).push<ManningRequirementsResult>(
      MaterialPageRoute(
        builder: (_) => ManningRequirementsScreen(
          initialDeckDepartment: _deckDepartment
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(),
          initialEngineDepartment: _engineDepartment
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(),
          initialDeckFiles: Map<String, String>.from(_deckFiles),
          initialEngineFiles: Map<String, String>.from(_engineFiles),
          initialAuthorizedCrew: _authorizedCrewController.text,
          initialOthersNumber: _othersNumberController.text,
          positions: List<String>.from(_positions),
          licenses: List<String>.from(_licenses),
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _deckDepartment = result.deckDepartment;
        _engineDepartment = result.engineDepartment;
        _deckFiles = result.deckFiles;
        _engineFiles = result.engineFiles;
        _authorizedCrewController.text = result.authorizedCrew;
        _othersNumberController.text = result.othersNumber;
      });
    }
  }

  Widget _buildManningSummaryCard({
    required String title,
    required List<Map<String, dynamic>> entries,
    required Color accentColor,
  }) {
    final total = entries.fold<int>(
      0,
      (sum, entry) =>
          sum + (int.tryParse(entry['number']?.toString() ?? '0') ?? 0),
    );

    final previewEntries = entries.take(3).toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(color: accentColor.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              gradient: LinearGradient(
                colors: [
                  accentColor.withOpacity(0.85),
                  accentColor,
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'TOTAL: $total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No positions added yet. Tap "Open Manning Requirements Form" to manage entries.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            )
          else
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.04),
                  ),
                  child: Row(
                    children: const [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Position',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'License',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Number',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...previewEntries.map(
                  (entry) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey.withOpacity(0.12),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            entry['position']?.toString() ?? '-',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            entry['license']?.toString() ?? '-',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            entry['number']?.toString() ?? '0',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (entries.length > previewEntries.length)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Text(
                      '+ ${entries.length - previewEntries.length} more entries',
                      style: TextStyle(
                        fontSize: 12,
                        color: accentColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPsscSummaryCard() {
    final authorizedCrew = int.tryParse(_authorizedCrewController.text) ?? 0;
    final others = int.tryParse(_othersNumberController.text) ?? 0;
    final total = authorizedCrew + others;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFF1B8A5A).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              gradient: LinearGradient(
                colors: [Color(0xFF14835A), Color(0xFF1B8A5A)],
              ),
            ),
            child: const Text(
              'PSSC (TOTAL PERSONS ONBOARD)',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                _buildPsscSummaryRow(
                  label: 'Authorized Crew',
                  value: authorizedCrew.toString(),
                ),
                const SizedBox(height: 8),
                _buildPsscSummaryRow(
                  label: 'Others (Support)',
                  value: others.toString(),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
              color: Color(0xFF0F6C46),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  total.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPsscSummaryRow({
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2D3D),
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Color(0xFF1B8A5A),
          ),
        ),
      ],
    );
  }

  Step _buildStep4() {
    return Step(
      title: const Text('Certificates'),
      isActive: _currentStep >= 3,
      state: _currentStep > 3 ? StepState.complete : StepState.indexed,
      content: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Card(
              color: Colors.blue[50],
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Optional: Certificates can be added later',
                        style: TextStyle(color: Colors.blue, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // NO EXPIRY Section
            Text(
              'NO EXPIRY',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 8),
            _buildNoExpiryCertificate(
              'Certificate of Philippine Registry',
              _philippineRegistryDateController,
              'philippineRegistry',
            ),
            const SizedBox(height: 8),
            _buildNoExpiryCertificate(
              'Certificate of Ownership',
              _ownershipDateController,
              'ownership',
            ),
            const SizedBox(height: 8),
            _buildNoExpiryCertificate(
              'Tonnage Measurement',
              _tonnageDateController,
              'tonnage',
            ),
            const SizedBox(height: 20),

            // WITH EXPIRY Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'WITH EXPIRY',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
                TextButton.icon(
                  onPressed: _addExpiryCertificate,
                  icon: Icon(Icons.add, size: 18),
                  label: Text('Add', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Existing expiry certificates - Optimized List View
            if (_expiryCertificates.isEmpty)
              SizedBox.shrink()
            else
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: _expiryCertificates.length,
                itemBuilder: (context, index) {
                  final cert = _expiryCertificates[index];
                  // Only calculate status if dates exist
                  final dateExpiry =
                      cert['dateExpiry']?.toString().trim() ?? '';
                  final dateIssued =
                      cert['dateIssued']?.toString().trim() ?? '';

                  // Debug output
                  if (dateExpiry.isNotEmpty) {
                    print(
                      'Calculating expiry status - Date Issued: $dateIssued, Date Expiry: $dateExpiry',
                    );
                  }

                  final expiryStatus = dateExpiry.isNotEmpty
                      ? _calculateExpiryStatus(
                          dateExpiry,
                          dateIssued: dateIssued.isNotEmpty ? dateIssued : null,
                        )
                      : {'days': 0, 'months': 0, 'years': 0};

                  if (dateExpiry.isNotEmpty) {
                    print(
                      'Expiry Status Result: Days: ${expiryStatus['days']}, Months: ${expiryStatus['months']}, Years: ${expiryStatus['years']}',
                    );
                  }

                  final statusText = dateExpiry.isNotEmpty
                      ? _getExpiryStatusText(expiryStatus)
                      : 'NOT SET';
                  final statusColor = dateExpiry.isNotEmpty
                      ? _getExpiryStatusColor(statusText)
                      : Colors.grey;
                  final hasFile = _expiryFiles[cert['id'].toString()] != null;

                  return Card(
                    margin: EdgeInsets.only(bottom: 8),
                    color: Colors.orange[50],
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Certificate Type:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    _deleteExpiryCertificate(cert['id']),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                              ),
                            ],
                          ),
                          DropdownButtonFormField<String>(
                            value:
                                cert['certificateType'].isEmpty ||
                                    !_certificateTypes.contains(
                                      cert['certificateType'],
                                    )
                                ? null
                                : cert['certificateType'],
                            isExpanded: true,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: 'Select Certificate',
                              hintStyle: TextStyle(fontSize: 11),
                            ),
                            items: _certificateTypes
                                .map(
                                  (type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(
                                      type,
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => _updateExpiryCertificate(
                              cert['id'],
                              'certificateType',
                              value ?? '',
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Date Issued:',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: TextEditingController(
                                    text: cert['dateIssued'],
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    suffixIcon: Icon(
                                      Icons.calendar_today,
                                      size: 16,
                                    ),
                                  ),
                                  style: TextStyle(fontSize: 11),
                                  readOnly: true,
                                  onTap: () => _selectExpiryCertificateDate(
                                    cert['id'],
                                    'dateIssued',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Date Expiry:',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: TextEditingController(
                                    text: cert['dateExpiry'],
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    suffixIcon: Icon(
                                      Icons.calendar_today,
                                      size: 16,
                                    ),
                                  ),
                                  style: TextStyle(fontSize: 11),
                                  readOnly: true,
                                  onTap: () => _selectExpiryCertificateDate(
                                    cert['id'],
                                    'dateExpiry',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          // Expiry Status Display
                          if (cert['dateExpiry']
                              .toString()
                              .trim()
                              .isNotEmpty) ...[
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'EXPIRY STATUS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildExpiryBox(
                                        'DAYS',
                                        expiryStatus['days']!.toString(),
                                      ),
                                      _buildExpiryBox(
                                        'MONTHS',
                                        expiryStatus['months']!.toString(),
                                      ),
                                      _buildExpiryBox(
                                        'YEARS',
                                        expiryStatus['years']!.toString(),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 8),
                          ],
                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _scanExpiryCertificate(cert['id']),
                                  icon: Icon(Icons.qr_code_scanner, size: 14),
                                  label: Text(
                                    'Scan',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 4),
                                    minimumSize: Size.zero,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _uploadExpiryFile(cert['id']),
                                  icon: Icon(Icons.upload, size: 14),
                                  label: Text(
                                    'Upload',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 4),
                                    minimumSize: Size.zero,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // File actions if file exists
                          if (hasFile) ...[
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _expiryFiles[cert['id'].toString()]!,
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.visibility, size: 16),
                                  onPressed: () =>
                                      _viewFileForMember('expiry', cert['id']),
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                ),
                                IconButton(
                                  icon: Icon(Icons.edit, size: 16),
                                  onPressed: () =>
                                      _uploadExpiryFile(cert['id']),
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteFileForMember(
                                    'expiry',
                                    cert['id'],
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),

            // No expiry certificates message
            if (_expiryCertificates.isEmpty)
              Card(
                color: Colors.grey[100],
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No expiry certificates added yet. Tap "Add" to add one.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoExpiryCertificate(
    String certificateName,
    TextEditingController dateController,
    String certId,
  ) {
    final validityStatus = _calculateValidityStatus(dateController.text);
    final hasFile = _noExpiryFiles[certId] != null;

    return Card(
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    certificateName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: validityStatus == 'VALID'
                        ? Colors.green
                        : Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    validityStatus,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('Date Issued:', style: TextStyle(fontSize: 11)),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: dateController,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                    ),
                    style: TextStyle(fontSize: 11),
                    readOnly: true,
                    onTap: () => _selectCertificateDate(dateController),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            // File upload section
            Row(
              children: [
                Expanded(child: Text('File:', style: TextStyle(fontSize: 11))),
                if (!hasFile) ...[
                  ElevatedButton.icon(
                    onPressed: () => _uploadNoExpiryFile(certId),
                    icon: Icon(Icons.upload, size: 14),
                    label: Text('Upload', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: Text(
                      _noExpiryFiles[certId]!
                          .split('/')
                          .last, // Show only filename
                      style: TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.visibility, size: 16),
                    onPressed: () => _viewFileForMember('noexpiry', certId),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 16),
                    onPressed: () => _uploadNoExpiryFile(certId),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, size: 16, color: Colors.red),
                    onPressed: () => _deleteFileForMember('noexpiry', certId),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Step _buildStep5() {
    return Step(
      title: const Text('Officers & Crew'),
      isActive: _currentStep >= 4,
      state: StepState.indexed,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            color: Colors.blue[50],
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add officers and crew with certificates. Use OCR to automatically extract data from SIRB, COC, or License certificates.',
                      style: TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                  ),
                ],
              ),
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
          // Filter Tabs
          Container(
            color: Colors.grey[200],
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _crewTabIndex = 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _crewTabIndex == 0
                            ? Colors.blue
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: _crewTabIndex == 0
                                ? Colors.blue
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'SIRB (${_sirbMembers.length})',
                          style: TextStyle(
                            color: _crewTabIndex == 0
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _crewTabIndex == 1
                            ? Colors.green
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: _crewTabIndex == 1
                                ? Colors.green
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'COC (${_competencyCertificates.length})',
                          style: TextStyle(
                            color: _crewTabIndex == 1
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _crewTabIndex == 2
                            ? Colors.orange
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: _crewTabIndex == 2
                                ? Colors.orange
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'License (${_competencyLicenses.length})',
                          style: TextStyle(
                            color: _crewTabIndex == 2
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tab Content - Use ListView.builder for better performance
          SizedBox(
            height: 400, // Fixed height for scrollable content
            child: IndexedStack(
              index: _crewTabIndex,
              children: [
                // SIRB Tab
                _buildCrewTab(
                  _sirbMembers,
                  _buildSirbCard,
                  _addSirbMember,
                  'SIRB',
                  Colors.blue,
                  'No SIRB entries added yet. Tap "Add" to add one.',
                ),
                // COC Tab
                _buildCrewTab(
                  _competencyCertificates,
                  _buildCompetencyCard,
                  _addCompetencyCertificate,
                  'COC',
                  Colors.green,
                  'No Certificate of Competency entries added yet. Tap "Add" to add one.',
                ),
                // License Tab
                _buildCrewTab(
                  _competencyLicenses,
                  _buildLicenseCard,
                  _addCompetencyLicense,
                  'License',
                  Colors.orange,
                  'No License entries added yet. Tap "Add" to add one.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrewTab(
    List<Map<String, dynamic>> items,
    Widget Function(Map<String, dynamic>) cardBuilder,
    VoidCallback onAdd,
    String title,
    MaterialColor color,
    String emptyMessage,
  ) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color.shade800,
                  ),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: Icon(Icons.add, size: 18, color: color.shade800),
                  label: Text(
                    'Add',
                    style: TextStyle(fontSize: 12, color: color.shade800),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Card(
              color: Colors.grey[100],
              margin: EdgeInsets.all(12),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  emptyMessage,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: cardBuilder(items[index]),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    MaterialColor color,
    VoidCallback onAdd,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color.shade800,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        SizedBox(width: 8),
        TextButton.icon(
          onPressed: onAdd,
          icon: Icon(Icons.add, size: 18, color: color.shade800),
          label: Text(
            'Add',
            style: TextStyle(fontSize: 12, color: color.shade800),
          ),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  // Show dialog to select certificate type when adding crew
  void _showAddCrewDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Add Crew Member',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Select the certificate type for this crew member:',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          // SIRB option
          ListTile(
            leading: Icon(Icons.badge, color: Colors.blue.shade700),
            title: const Text('SIRB', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Seafarer Identification and Record Book (${_sirbMembers.length})',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue.shade700),
            onTap: () {
              Navigator.of(context).pop();
              setState(() {
                _crewTabIndex = 0; // Switch to SIRB tab
                _addSirbMember();
              });
            },
          ),
          const Divider(),
          // COC option
          ListTile(
            leading: Icon(Icons.card_membership, color: Colors.green.shade700),
            title: const Text('COC', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Certificate of Competency (${_competencyCertificates.length})',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.green.shade700),
            onTap: () {
              Navigator.of(context).pop();
              setState(() {
                _crewTabIndex = 1; // Switch to COC tab
                _addCompetencyCertificate();
              });
            },
          ),
          const Divider(),
          // License option
          ListTile(
            leading: Icon(Icons.verified, color: Colors.orange.shade700),
            title: const Text('License', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'License Certificate (${_competencyLicenses.length})',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.orange.shade700),
            onTap: () {
              Navigator.of(context).pop();
              setState(() {
                _crewTabIndex = 2; // Switch to License tab
                _addCompetencyLicense();
              });
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // SIRB Table Methods
  void _addSirbMember() {
    setState(() {
      _sirbMembers.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': '',
        'position': '',
        'dateExpiry': '',
      });
    });
  }

  void _deleteSirbMember(int id) {
    setState(() {
      _sirbMembers.removeWhere((member) => member['id'] == id);
      _sirbFiles.remove(id.toString());
    });
  }

  void _updateSirbMember(int id, String field, dynamic value) {
    final index = _sirbMembers.indexWhere((member) => member['id'] == id);
    if (index != -1 && _sirbMembers[index][field] != value) {
      setState(() {
        _sirbMembers[index][field] = value;
      });
    }
  }

  // Certificate of Competency Table Methods
  void _addCompetencyCertificate() {
    setState(() {
      _competencyCertificates.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': '',
        'position': '',
        'dateExpiry': '',
      });
    });
  }

  void _deleteCompetencyCertificate(int id) {
    setState(() {
      _competencyCertificates.removeWhere((cert) => cert['id'] == id);
      _competencyFiles.remove(id.toString());
    });
  }

  void _updateCompetencyCertificate(int id, String field, dynamic value) {
    final index = _competencyCertificates.indexWhere(
      (cert) => cert['id'] == id,
    );
    if (index != -1 && _competencyCertificates[index][field] != value) {
      setState(() {
        _competencyCertificates[index][field] = value;
      });
    }
  }

  // License Table Methods
  void _addCompetencyLicense() {
    setState(() {
      _competencyLicenses.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'licenseType': '',
        'name': '',
        'dateExpiry': '',
      });
    });
  }

  void _deleteCompetencyLicense(int id) {
    setState(() {
      _competencyLicenses.removeWhere((license) => license['id'] == id);
      _licenseFiles.remove(id.toString());
    });
  }

  void _updateCompetencyLicense(int id, String field, dynamic value) {
    final index = _competencyLicenses.indexWhere(
      (license) => license['id'] == id,
    );
    if (index != -1 && _competencyLicenses[index][field] != value) {
      setState(() {
        _competencyLicenses[index][field] = value;
      });
    }
  }

  void _addCrewMember() {
    setState(() {
      _crewMembers.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': '',
        'position': '',
        'expiryDate': '',
        'licenseNumber': '',
      });
    });
  }

  void _deleteCrewMember(int id) {
    setState(() {
      _crewMembers.removeWhere((member) => member['id'] == id);
      _crewFiles.remove(id.toString());
    });
  }

  void _updateCrewMember(int id, String field, dynamic value) {
    final index = _crewMembers.indexWhere((member) => member['id'] == id);
    if (index != -1 && _crewMembers[index][field] != value) {
      setState(() {
        _crewMembers[index][field] = value;
      });
    }
  }

  // SIRB Card Builder
  Widget _buildSirbCard(Map<String, dynamic> member) {
    final hasFile = _sirbFiles[member['id'].toString()] != null;
    final expiryStatus = member['dateExpiry'].toString().isNotEmpty
        ? _calculateExpiryStatus(
            member['dateExpiry'].toString(),
            dateIssued: member['dateIssued']?.toString(),
          )
        : {'days': 0, 'months': 0, 'years': 0};
    final statusText = member['dateExpiry'].toString().isNotEmpty
        ? _getExpiryStatusText(expiryStatus)
        : 'NOT SET';
    final statusColor = member['dateExpiry'].toString().isNotEmpty
        ? _getExpiryStatusColor(statusText)
        : Colors.grey;

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'SIRB',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red, size: 18),
                  onPressed: () => _deleteSirbMember(member['id']),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
            SizedBox(height: 4),
            TextFormField(
              key: ValueKey('sirb_name_${member['id']}'),
              initialValue: member['name']?.toString() ?? '',
              decoration: InputDecoration(
                labelText: 'Name *',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              textCapitalization: TextCapitalization.words,
              style: TextStyle(fontSize: 11),
              onChanged: (value) =>
                  _updateSirbMember(member['id'], 'name', value),
            ),
            SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _getMatchingPosition(member['position']?.toString()),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Position',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              items: _positions
                  .toSet() // Remove duplicates
                  .map(
                    (pos) => DropdownMenuItem(
                      value: pos,
                      child: Text(pos, style: TextStyle(fontSize: 11)),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  _updateSirbMember(member['id'], 'position', value ?? ''),
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text('Expiry Date:', style: TextStyle(fontSize: 11)),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: TextEditingController(
                      text: member['dateExpiry'] ?? '',
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                    ),
                    style: TextStyle(fontSize: 11),
                    readOnly: true,
                    onTap: () => _selectExpiryDate('sirb', member['id']),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _scanCertificate('sirb', member['id']),
                    icon: Icon(Icons.qr_code_scanner, size: 14),
                    label: Text('Scan', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _uploadFile('sirb', member['id']),
                    icon: Icon(Icons.upload, size: 14),
                    label: Text('Upload', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
              ],
            ),
            if (hasFile) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _sirbFiles[member['id'].toString()]!.split('/').last,
                      style: TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.visibility, size: 16),
                    onPressed: () => _viewFileForMember('sirb', member['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 16),
                    onPressed: () => _uploadFile('sirb', member['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, size: 16, color: Colors.red),
                    onPressed: () => _deleteFileForMember('sirb', member['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Certificate of Competency Card Builder
  Widget _buildCompetencyCard(Map<String, dynamic> cert) {
    final hasFile = _competencyFiles[cert['id'].toString()] != null;
    final expiryStatus = cert['dateExpiry'].toString().isNotEmpty
        ? _calculateExpiryStatus(
            cert['dateExpiry'].toString(),
            dateIssued: cert['dateIssued']?.toString(),
          )
        : {'days': 0, 'months': 0, 'years': 0};
    final statusText = cert['dateExpiry'].toString().isNotEmpty
        ? _getExpiryStatusText(expiryStatus)
        : 'NOT SET';
    final statusColor = cert['dateExpiry'].toString().isNotEmpty
        ? _getExpiryStatusColor(statusText)
        : Colors.grey;

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      color: Colors.green[50],
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Certificate of Competency',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red, size: 18),
                  onPressed: () => _deleteCompetencyCertificate(cert['id']),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
            SizedBox(height: 4),
            TextFormField(
              key: ValueKey('coc_name_${cert['id']}'),
              initialValue: cert['name']?.toString() ?? '',
              decoration: InputDecoration(
                labelText: 'Name *',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              textCapitalization: TextCapitalization.words,
              style: TextStyle(fontSize: 11),
              onChanged: (value) =>
                  _updateCompetencyCertificate(cert['id'], 'name', value),
            ),
            SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _getMatchingPosition(cert['position']?.toString()),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Position',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              items: _positions
                  .toSet() // Remove duplicates
                  .map(
                    (pos) => DropdownMenuItem(
                      value: pos,
                      child: Text(pos, style: TextStyle(fontSize: 11)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => _updateCompetencyCertificate(
                cert['id'],
                'position',
                value ?? '',
              ),
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text('Expiry Date:', style: TextStyle(fontSize: 11)),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: TextEditingController(
                      text: cert['dateExpiry'] ?? '',
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                    ),
                    style: TextStyle(fontSize: 11),
                    readOnly: true,
                    onTap: () => _selectExpiryDate('competency', cert['id']),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _scanCertificate('competency', cert['id']),
                    icon: Icon(Icons.qr_code_scanner, size: 14),
                    label: Text('Scan', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _uploadFile('competency', cert['id']),
                    icon: Icon(Icons.upload, size: 14),
                    label: Text('Upload', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
              ],
            ),
            if (hasFile) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _competencyFiles[cert['id'].toString()]!.split('/').last,
                      style: TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.visibility, size: 16),
                    onPressed: () =>
                        _viewFileForMember('competency', cert['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 16),
                    onPressed: () => _uploadFile('competency', cert['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, size: 16, color: Colors.red),
                    onPressed: () =>
                        _deleteFileForMember('competency', cert['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // License Card Builder
  Widget _buildLicenseCard(Map<String, dynamic> license) {
    final hasFile = _licenseFiles[license['id'].toString()] != null;
    final expiryStatus = license['dateExpiry'].toString().isNotEmpty
        ? _calculateExpiryStatus(
            license['dateExpiry'].toString(),
            dateIssued: license['dateIssued']?.toString(),
          )
        : {'days': 0, 'months': 0, 'years': 0};
    final statusText = license['dateExpiry'].toString().isNotEmpty
        ? _getExpiryStatusText(expiryStatus)
        : 'NOT SET';
    final statusColor = license['dateExpiry'].toString().isNotEmpty
        ? _getExpiryStatusColor(statusText)
        : Colors.grey;

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      color: Colors.orange[50],
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'License',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red, size: 18),
                  onPressed: () => _deleteCompetencyLicense(license['id']),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
            SizedBox(height: 4),
            DropdownButtonFormField<String>(
              key: ValueKey('license_type_${license['id']}'),
              value: license['licenseType'] != null &&
                      license['licenseType'].toString().isNotEmpty &&
                      _licenses.contains(license['licenseType'])
                  ? license['licenseType']
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'License Type',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              items: _licenses
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type, style: TextStyle(fontSize: 11)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => _updateCompetencyLicense(
                license['id'],
                'licenseType',
                value ?? '',
              ),
            ),
            SizedBox(height: 4),
            TextFormField(
              key: ValueKey('license_name_${license['id']}'),
              initialValue: license['name']?.toString() ?? '',
              decoration: InputDecoration(
                labelText: 'Name *',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              textCapitalization: TextCapitalization.words,
              style: TextStyle(fontSize: 11),
              onChanged: (value) =>
                  _updateCompetencyLicense(license['id'], 'name', value),
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text('Expiry Date:', style: TextStyle(fontSize: 11)),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: TextEditingController(
                      text: license['dateExpiry'] ?? '',
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                    ),
                    style: TextStyle(fontSize: 11),
                    readOnly: true,
                    onTap: () => _selectExpiryDate('license', license['id']),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _scanCertificate('license', license['id']),
                    icon: Icon(Icons.qr_code_scanner, size: 14),
                    label: Text('Scan', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _uploadFile('license', license['id']),
                    icon: Icon(Icons.upload, size: 14),
                    label: Text('Upload', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
              ],
            ),
            if (hasFile) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _licenseFiles[license['id'].toString()]!.split('/').last,
                      style: TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.visibility, size: 16),
                    onPressed: () =>
                        _viewFileForMember('license', license['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 16),
                    onPressed: () => _uploadFile('license', license['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, size: 16, color: Colors.red),
                    onPressed: () =>
                        _deleteFileForMember('license', license['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCrewCard(Map<String, dynamic> member) {
    final hasFile = _crewFiles[member['id'].toString()] != null;
    final expiryStatus = member['expiryDate'].toString().isNotEmpty
        ? _calculateExpiryStatus(
            member['expiryDate'].toString(),
            dateIssued: member['dateIssued']?.toString(),
          )
        : {'days': 0, 'months': 0, 'years': 0};
    final statusText = member['expiryDate'].toString().isNotEmpty
        ? _getExpiryStatusText(expiryStatus)
        : 'NOT SET';
    final statusColor = member['expiryDate'].toString().isNotEmpty
        ? _getExpiryStatusColor(statusText)
        : Colors.grey;

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Crew Member',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red, size: 18),
                  onPressed: () => _deleteCrewMember(member['id']),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
            SizedBox(height: 4),
            // Name field
            TextFormField(
              controller: TextEditingController(text: member['name']),
              decoration: InputDecoration(
                labelText: 'Name *',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              style: TextStyle(fontSize: 11),
              onChanged: (value) =>
                  _updateCrewMember(member['id'], 'name', value),
            ),
            SizedBox(height: 4),
            // Position field
            DropdownButtonFormField<String>(
              value: _getMatchingPosition(member['position']?.toString()),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Position',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              items: _positions
                  .toSet() // Remove duplicates
                  .map(
                    (pos) => DropdownMenuItem(
                      value: pos,
                      child: Text(pos, style: TextStyle(fontSize: 11)),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  _updateCrewMember(member['id'], 'position', value ?? ''),
            ),
            SizedBox(height: 4),
            // License Number
            TextFormField(
              controller: TextEditingController(text: member['licenseNumber']),
              decoration: InputDecoration(
                labelText: 'License/Certificate Number',
                isDense: true,
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontSize: 11),
              ),
              style: TextStyle(fontSize: 11),
              onChanged: (value) =>
                  _updateCrewMember(member['id'], 'licenseNumber', value),
            ),
            SizedBox(height: 4),
            // Expiry Date
            Row(
              children: [
                Expanded(
                  child: Text('Expiry Date:', style: TextStyle(fontSize: 11)),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: TextEditingController(
                      text: member['expiryDate'],
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                    ),
                    style: TextStyle(fontSize: 11),
                    readOnly: true,
                    onTap: () => _selectCrewExpiryDate(member['id']),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _scanCrewCertificate(member['id']),
                    icon: Icon(Icons.qr_code_scanner, size: 14),
                    label: Text(
                      'Scan Certificate',
                      style: TextStyle(fontSize: 10),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _uploadCrewFile(member['id']),
                    icon: Icon(Icons.upload, size: 14),
                    label: Text('Upload', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
              ],
            ),
            // File actions if file exists
            if (hasFile) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _crewFiles[member['id'].toString()]?.split('/').last ??
                          'Unknown file',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.visibility, size: 16),
                    onPressed: () => _viewFileForMember('crew', member['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 16),
                    onPressed: () => _uploadCrewFile(member['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, size: 16, color: Colors.red),
                    onPressed: () => _deleteFileForMember('crew', member['id']),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _selectCrewExpiryDate(int crewId) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _updateCrewMember(
          crewId,
          'expiryDate',
          '${picked.day}/${picked.month}/${picked.year}',
        );
      });
    }
  }

  void _uploadCrewFile(int crewId) async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select File Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _crewFiles[crewId.toString()] = image.path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File uploaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload file'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _selectCertificateDate(TextEditingController dateController) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        dateController.text = '${picked.day}/${picked.month}/${picked.year}';
      });
    }
  }

  void _addExpiryCertificate() {
    setState(() {
      _expiryCertificates.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'certificateType': '',
        'dateIssued': '',
        'dateExpiry': '',
      });
    });
  }

  void _scanCrewCertificate(int crewId) async {
    try {
      // Show dialog to choose camera or gallery
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Scan Certificate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      // Pick image
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Scanning certificate...'),
            ],
          ),
        ),
      );

      try {
        // Process OCR
        final result = await _ocrService.recognizeText(image.path);

        if (result['text'] == null ||
            result['text'].toString().trim().isEmpty) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No text detected in the image. Please ensure the certificate is clearly visible.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        // Extract crew data using enhanced service
        final dataExtractionService = DataExtractionService();

        // Try COC first (Certificate of Competency)
        var extractedData = dataExtractionService.extractCOCData(
          result['text'],
        );

        // If COC extraction didn't find name, try general crew extraction (for SIRB)
        if (extractedData['name'] == null ||
            extractedData['name'].toString().isEmpty) {
          extractedData = dataExtractionService.extractCrewData(result['text']);
        }

        // Close loading
        Navigator.pop(context);

        // Update crew member data
        setState(() {
          if (extractedData['name'] != null &&
              extractedData['name'].toString().isNotEmpty) {
            _updateCrewMember(crewId, 'name', extractedData['name']);
          }
          if (extractedData['position'] != null &&
              extractedData['position'].toString().isNotEmpty) {
            _updateCrewMember(crewId, 'position', extractedData['position']);
          }
          if (extractedData['expiryDate'] != null &&
              extractedData['expiryDate'].toString().isNotEmpty) {
            // Convert normalized date (YYYY-MM-DD) back to DD/MM/YYYY for display
            final dateStr = extractedData['expiryDate'].toString();
            if (dateStr.contains('-')) {
              final parts = dateStr.split('-');
              _updateCrewMember(
                crewId,
                'expiryDate',
                '${parts[2]}/${parts[1]}/${parts[0]}',
              );
            } else {
              _updateCrewMember(crewId, 'expiryDate', dateStr);
            }
          }
          if (extractedData['certificateNumber'] != null &&
              extractedData['certificateNumber'].toString().isNotEmpty) {
            _updateCrewMember(
              crewId,
              'licenseNumber',
              extractedData['certificateNumber'],
            );
          }
          _crewFiles[crewId.toString()] = image.path;
        });

        // Show success message
        final extractedFields = <String>[];
        if (extractedData['name'] != null)
          extractedFields.add('Name: ${extractedData['name']}');
        if (extractedData['position'] != null)
          extractedFields.add('Position: ${extractedData['position']}');
        if (extractedData['expiryDate'] != null)
          extractedFields.add('Expiry: ${extractedData['expiryDate']}');

        final message = extractedFields.isNotEmpty
            ? 'Certificate scanned successfully!\n\n${extractedFields.join('\n')}\n\nPlease review and complete the form if needed.'
            : 'Certificate scanned. Please review and complete the form manually.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      } catch (e) {
        Navigator.pop(context); // Close loading if open
        throw e;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to scan certificate: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  // Debounced validation for contact number
  void _validateContactNumberDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final contact = _contactNumberController.text.trim();
      String? error;

      if (contact.isEmpty) {
        // Don't show error on empty during typing
      } else if (contact.length != 11) {
        error = 'Contact number must be exactly 11 digits (09XX XXX XXXX)';
      } else if (!contact.startsWith('09')) {
        error = 'Contact number must start with 09';
      }

      if (_contactNumberError != error) {
        setState(() {
          _contactNumberError = error;
        });
      }
    });
  }

  Future<bool> _validateStep1() async {
    // Batch all errors in a single setState call
    String? vesselTypeError;
    String? vesselNameError;
    String? imoError;
    String? companyError;
    String? shippingCodeError;
    String? contactNumberError;
    String? masterError;
    String? chiefEngineerError;

    bool hasErrors = false;

    // 1. Vessel Type - Required
    if (_selectedVesselType.isEmpty || _selectedVesselType.trim() == '') {
      vesselTypeError = 'Vessel type is required';
      hasErrors = true;
    }

    // 2. Vessel Name - Required, no empty/whitespace
    final vesselName = _vesselNameController.text.trim();
    if (vesselName.isEmpty) {
      vesselNameError = 'Vessel name is required';
      hasErrors = true;
    }

    // 3. Official Number - Required, numbers only
    final imo = _imoNumberController.text.trim();
    if (imo.isEmpty) {
      imoError = 'Official number is required';
      hasErrors = true;
    } else {
      // Check if it contains only digits
      if (!RegExp(r'^[0-9]+$').hasMatch(imo)) {
        imoError = 'Official number must contain only numbers';
        hasErrors = true;
      }
    }

    // 4. Company/Owner - Required
    if (_selectedCompanyOwner.isEmpty || _selectedCompanyOwner.trim() == '') {
      companyError = 'Company/Owner is required';
      hasErrors = true;
    }

    // 5. Shipping Code - Required
    if (_shippingCodeController.text.trim().isEmpty) {
      shippingCodeError = 'Shipping Code is required';
      hasErrors = true;
    }

    // 6. Contact Number - Must be exactly 11 digits
    final contact = _contactNumberController.text.trim();
    if (contact.isEmpty) {
      contactNumberError = 'Contact number is required';
      hasErrors = true;
    } else if (contact.length != 11) {
      contactNumberError =
          'Contact number must be exactly 11 digits (09XX XXX XXXX)';
      hasErrors = true;
    } else if (!contact.startsWith('09')) {
      contactNumberError = 'Contact number must start with 09';
      hasErrors = true;
    }

    // 7. Master - Required
    if (_masterController.text.trim().isEmpty) {
      masterError = 'Master name is required';
      hasErrors = true;
    }

    // 8. Chief Engineer - Required
    if (_chiefEngineerController.text.trim().isEmpty) {
      chiefEngineerError = 'Chief Engineer name is required';
      hasErrors = true;
    }

    // Update all errors in a single setState call
    setState(() {
      _vesselTypeError = vesselTypeError;
      _vesselNameError = vesselNameError;
      _imoError = imoError;
      _companyError = companyError;
      _shippingCodeError = shippingCodeError;
      _contactNumberError = contactNumberError;
      _masterError = masterError;
      _chiefEngineerError = chiefEngineerError;
    });

    return !hasErrors;
  }

  Future<bool> _validateStep2() async {
    // Batch all errors in a single setState call
    String? typeOfShipError;
    String? grossTonnageError;
    String? netTonnageError;
    String? placeBuiltError;
    String? yearBuiltError;
    String? builderError;
    String? lengthError;
    String? homeportError;
    String? hullMaterialError;
    String? numberOfEnginesError;
    String? kilowattError;

    bool hasErrors = false;

    // 1. Type of Ship - Required
    if (_typeOfShipController.text.trim().isEmpty) {
      typeOfShipError = 'Type of ship is required';
      hasErrors = true;
    }

    // 2. Gross Tonnage - Required, positive number
    final grossTonnage = _grossTonnageController.text.trim();
    if (grossTonnage.isEmpty) {
      grossTonnageError = 'Gross tonnage is required';
      hasErrors = true;
    } else {
      final value = double.tryParse(grossTonnage);
      if (value == null) {
        grossTonnageError = 'Gross tonnage must be a valid number';
        hasErrors = true;
      } else if (value <= 0) {
        grossTonnageError = 'Gross tonnage must be a positive number';
        hasErrors = true;
      }
    }

    // 3. Net Tonnage - Required, positive number, not greater than gross
    final netTonnage = _netTonnageController.text.trim();
    if (netTonnage.isEmpty) {
      netTonnageError = 'Net tonnage is required';
      hasErrors = true;
    } else {
      final value = double.tryParse(netTonnage);
      if (value == null) {
        netTonnageError = 'Net tonnage must be a valid number';
        hasErrors = true;
      } else if (value <= 0) {
        netTonnageError = 'Net tonnage must be a positive number';
        hasErrors = true;
      } else {
        final grossValue = double.tryParse(_grossTonnageController.text.trim());
        if (grossValue != null && value > grossValue) {
          netTonnageError = 'Net tonnage cannot be greater than gross tonnage';
          hasErrors = true;
        }
      }
    }

    // 4. Place Built - Required
    if (_placeBuiltController.text.trim().isEmpty) {
      placeBuiltError = 'Place built is required';
      hasErrors = true;
    }

    // 5. Year Built - Required, not future, not before 1970
    final yearBuilt = _yearBuiltController.text.trim();
    if (yearBuilt.isEmpty) {
      yearBuiltError = 'Year built is required';
      hasErrors = true;
    } else {
      // Just year format (manual input)
      final year = int.tryParse(yearBuilt);

      if (year == null) {
        yearBuiltError = 'Year built must be a valid year';
        hasErrors = true;
      } else {
        final currentYear = DateTime.now().year;
        if (year < 1970) {
          yearBuiltError = 'Year built cannot be before 1970';
          hasErrors = true;
        } else if (year > currentYear) {
          yearBuiltError = 'Year built cannot be in the future';
          hasErrors = true;
        }
      }
    }

    // 6. Builder - Required
    if (_builderController.text.trim().isEmpty) {
      builderError = 'Builder is required';
      hasErrors = true;
    }

    // 7. Length - Required
    if (_lengthController.text.trim().isEmpty) {
      lengthError = 'Length is required';
      hasErrors = true;
    }

    // 8. Homeport - Required
    if (_homeportController.text.trim().isEmpty) {
      homeportError = 'Homeport is required';
      hasErrors = true;
    }

    // 9. Hull Material - Required
    if (_selectedHullMaterial.isEmpty || _selectedHullMaterial.trim() == '') {
      hullMaterialError = 'Hull material is required';
      hasErrors = true;
    }

    // 10. Number of Engines - Required, integer >= 1
    final numberOfEngines = _numberOfEnginesController.text.trim();
    if (numberOfEngines.isEmpty) {
      numberOfEnginesError = 'Number of engines is required';
      hasErrors = true;
    } else {
      final value = int.tryParse(numberOfEngines);
      if (value == null) {
        numberOfEnginesError = 'Number of engines must be a valid integer';
        hasErrors = true;
      } else if (value < 1) {
        numberOfEnginesError = 'Number of engines must be at least 1';
        hasErrors = true;
      }
    }

    // 11. Kilowatt - Required, positive number
    final kilowatt = _kilowattController.text.trim();
    if (kilowatt.isEmpty) {
      kilowattError = 'Kilowatt is required';
      hasErrors = true;
    } else {
      final value = double.tryParse(kilowatt);
      if (value == null) {
        kilowattError = 'Kilowatt must be a valid number';
        hasErrors = true;
      } else if (value <= 0) {
        kilowattError = 'Kilowatt must be a positive number';
        hasErrors = true;
      }
    }

    // Update all errors in a single setState call
    setState(() {
      _typeOfShipError = typeOfShipError;
      _grossTonnageError = grossTonnageError;
      _netTonnageError = netTonnageError;
      _placeBuiltError = placeBuiltError;
      _yearBuiltError = yearBuiltError;
      _builderError = builderError;
      _lengthError = lengthError;
      _homeportError = homeportError;
      _hullMaterialError = hullMaterialError;
      _numberOfEnginesError = numberOfEnginesError;
      _kilowattError = kilowattError;
    });

    return !hasErrors;
  }

  Future<bool> _validateStep3() async {
    // Batch all errors in a single setState call
    String? authorizedCrewError;
    String? othersNumberError;

    bool hasErrors = false;

    // Validate Authorized Crew
    final authorizedCrew = int.tryParse(_authorizedCrewController.text);
    if (authorizedCrew == null || authorizedCrew <= 0) {
      authorizedCrewError = 'Authorized crew must be a positive number';
      hasErrors = true;
    }

    // Validate Others Number
    final othersNumber = int.tryParse(_othersNumberController.text);
    if (othersNumber == null || othersNumber < 0) {
      othersNumberError = 'Others number must be 0 or more';
      hasErrors = true;
    }

    // Update all errors in a single setState call
    setState(() {
      _authorizedCrewError = authorizedCrewError;
      _othersNumberError = othersNumberError;
    });

    return !hasErrors;
  }

  Future<bool> _validateStep4() async {
    final certificateConfigs = [
      {
        'id': 'philippineRegistry',
        'date': _philippineRegistryDateController.text.trim(),
      },
      {
        'id': 'ownership',
        'date': _ownershipDateController.text.trim(),
      },
      {
        'id': 'tonnage',
        'date': _tonnageDateController.text.trim(),
      },
    ];

    final invalidDates = <String>[];
    final missingFiles = <String>[];

    for (final config in certificateConfigs) {
      final certId = config['id'] as String;
      final dateIssued = (config['date'] as String).trim();
      final label = _noExpiryCertificateLabels[certId] ?? certId;
      final status = _calculateValidityStatus(dateIssued);

      if (status != 'VALID') {
        invalidDates.add(label);
        continue;
      }

      if (!_hasNoExpirySupportingFile(certId)) {
        missingFiles.add(label);
      }
    }

    if (invalidDates.isNotEmpty || missingFiles.isNotEmpty) {
      setState(() {}); // Refresh status chips to reflect current values

      final messages = <String>[];
      if (invalidDates.isNotEmpty) {
        messages.add(
          'Set a valid issued date (today or a past date) for: ${invalidDates.join(', ')}.',
        );
      }
      if (missingFiles.isNotEmpty) {
        messages.add(
          'Upload supporting files for: ${missingFiles.join(', ')}.',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messages.join('\n')),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    return true;
  }

  Future<bool> _validateStep5() async {
    final missingSections = <String>{};
    final issues = <String>{};

    if (_sirbMembers.isEmpty) {
      missingSections.add('SIRB');
    } else {
      var missingName = false;
      var missingPosition = false;
      var missingExpiry = false;
      var invalidExpiry = false;
      var missingFile = false;

      for (final member in _sirbMembers) {
        final name = member['name']?.toString().trim() ?? '';
        final position = member['position']?.toString().trim() ?? '';
        final expiry = member['dateExpiry']?.toString().trim() ?? '';

        if (name.isEmpty) missingName = true;
        if (position.isEmpty) missingPosition = true;
        if (expiry.isEmpty) {
          missingExpiry = true;
        } else if (_parseDate(expiry) == null) {
          invalidExpiry = true;
        }
        if (!_hasSupportingFile(member, _sirbFiles)) missingFile = true;
      }

      if (missingName) {
        issues.add('Provide a name for each SIRB entry.');
      }
      if (missingPosition) {
        issues.add('Select a position for each SIRB entry.');
      }
      if (missingExpiry) {
        issues.add('Set an expiry date for each SIRB entry.');
      }
      if (invalidExpiry) {
        issues.add('Use valid expiry dates for all SIRB entries.');
      }
      if (missingFile) {
        issues.add('Upload the supporting SIRB file for each entry.');
      }
    }

    if (_competencyCertificates.isEmpty) {
      missingSections.add('Certificate of Competency');
    } else {
      var missingName = false;
      var missingPosition = false;
      var missingExpiry = false;
      var invalidExpiry = false;
      var missingFile = false;

      for (final cert in _competencyCertificates) {
        final name = cert['name']?.toString().trim() ?? '';
        final position = cert['position']?.toString().trim() ?? '';
        final expiry = cert['dateExpiry']?.toString().trim() ?? '';

        if (name.isEmpty) missingName = true;
        if (position.isEmpty) missingPosition = true;
        if (expiry.isEmpty) {
          missingExpiry = true;
        } else if (_parseDate(expiry) == null) {
          invalidExpiry = true;
        }
        if (!_hasSupportingFile(cert, _competencyFiles)) missingFile = true;
      }

      if (missingName) {
        issues.add('Provide a name for each Certificate of Competency entry.');
      }
      if (missingPosition) {
        issues.add('Select a position for each Certificate of Competency entry.');
      }
      if (missingExpiry) {
        issues.add('Set an expiry date for each Certificate of Competency entry.');
      }
      if (invalidExpiry) {
        issues.add('Use valid expiry dates for all Certificate of Competency entries.');
      }
      if (missingFile) {
        issues.add('Upload the supporting Certificate of Competency file for each entry.');
      }
    }

    if (_competencyLicenses.isEmpty) {
      missingSections.add('License');
    } else {
      var missingLicenseType = false;
      var missingName = false;
      var missingExpiry = false;
      var invalidExpiry = false;
      var missingFile = false;

      for (final license in _competencyLicenses) {
        final licenseType = license['licenseType']?.toString().trim() ?? '';
        final name = license['name']?.toString().trim() ?? '';
        final expiry = license['dateExpiry']?.toString().trim() ?? '';

        if (licenseType.isEmpty) missingLicenseType = true;
        if (name.isEmpty) missingName = true;
        if (expiry.isEmpty) {
          missingExpiry = true;
        } else if (_parseDate(expiry) == null) {
          invalidExpiry = true;
        }
        if (!_hasSupportingFile(license, _licenseFiles)) missingFile = true;
      }

      if (missingLicenseType) {
        issues.add('Provide a license type for each License entry.');
      }
      if (missingName) {
        issues.add('Provide a name for each License entry.');
      }
      if (missingExpiry) {
        issues.add('Set an expiry date for each License entry.');
      }
      if (invalidExpiry) {
        issues.add('Use valid expiry dates for all License entries.');
      }
      if (missingFile) {
        issues.add('Upload the supporting License file for each entry.');
      }
    }

    if (missingSections.isNotEmpty || issues.isNotEmpty) {
      final messages = <String>[];
      if (missingSections.isNotEmpty) {
        messages.add('Add at least one entry for: ${missingSections.join(', ')}.');
      }
      messages.addAll(issues);

      _showErrorDialog('Complete Crew Details', messages.join('\n'));
      return false;
    }

    return true;
  }

  Future<void> _continue() async {
    // Validate current step before continuing
    if (_currentStep == 0) {
      final isValid = await _validateStep1();
      if (!isValid) {
        return; // Don't proceed if validation fails
      }
    } else if (_currentStep == 1) {
      final isValid = await _validateStep2();
      if (!isValid) {
        return; // Don't proceed if validation fails
      }
    } else if (_currentStep == 2) {
      final isValid = await _validateStep3();
      if (!isValid) {
        return; // Don't proceed if validation fails
      }
    } else if (_currentStep == 3 && !_isEditMode) {
      final isValid = await _validateStep4();
      if (!isValid) {
        return; // Don't proceed if validation fails
      }
    } else if (_currentStep == 4 && !_isEditMode) {
      final isValid = await _validateStep5();
      if (!isValid) {
        return; // Don't proceed if validation fails
      }
    }

    if (_isEditMode) {
      if (_currentStep < 2) {
        setState(() {
          _currentStep += 1;
          if (_currentStep == 2) {
            _shouldLaunchManningEditor = true;
          }
        });
      }
    } else {
      if (_currentStep < 4) {
        setState(() {
          _currentStep += 1;
          if (_currentStep == 2) {
            _shouldLaunchManningEditor = true;
          }
        });
      }
    }
  }

  void _cancel() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep -= 1;
        if (_currentStep < 2) {
          _shouldLaunchManningEditor = false;
        }
      });
    }
  }

  void _onStepTapped(int step) {
      setState(() {
        _currentStep = step;
        if (_currentStep < 2) {
          _shouldLaunchManningEditor = false;
        }
      });
    }


  /// Helper method to find matching position value, handling case differences
  /// Returns the exact position from _positions list if found (case-insensitive match)
  /// Returns null if no match is found
  String? _getMatchingPosition(String? positionValue) {
    if (positionValue == null || positionValue.isEmpty) {
      return null;
    }

    // First try exact match (case-sensitive)
    if (_positions.contains(positionValue)) {
      return positionValue;
    }

    // Try case-insensitive match
    final normalizedValue = positionValue.toUpperCase().trim();
    for (final pos in _positions) {
      if (pos.toUpperCase().trim() == normalizedValue) {
        return pos; // Return the exact value from _positions
      }
    }

    return null; // No match found
  }

  /// Helper method to find matching license value, handling case differences and variations
  /// Returns the exact license from _licenses list if found (case-insensitive match)
  /// Returns null if no match is found
  String? _getMatchingLicense(String? licenseValue) {
    if (licenseValue == null || licenseValue.isEmpty || 
        licenseValue == 'N.A' || licenseValue == 'N/A') {
      return licenseValue; // Keep special values as-is
    }

    // First try exact match (case-sensitive)
    if (_licenses.contains(licenseValue)) {
      return licenseValue;
    }

    // Try case-insensitive match
    final normalizedValue = licenseValue.toUpperCase().trim();
    for (final lic in _licenses) {
      if (lic.toUpperCase().trim() == normalizedValue) {
        return lic; // Return the exact value from _licenses
      }
    }

    // Handle common variations (e.g., "BOAT CAPTAIN 3" might be stored but not in list)
    // Try to find closest match (e.g., "BOAT CAPTAIN 3" -> "BOAT CAPTAIN 2" or "BOAT CAPTAIN 1")
    if (normalizedValue.contains('BOAT CAPTAIN')) {
      // If it's a boat captain variation, try to match to existing boat captain licenses
      for (final lic in _licenses) {
        if (lic.toUpperCase().contains('BOAT CAPTAIN')) {
          return lic; // Return the first matching boat captain license
        }
      }
    }

    return null; // No match found
  }
}



