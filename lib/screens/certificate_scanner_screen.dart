import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ocr_service.dart';
import '../services/data_extraction_service.dart';

class CertificateScannerScreen extends StatefulWidget {
  const CertificateScannerScreen({super.key});

  @override
  State<CertificateScannerScreen> createState() => _CertificateScannerScreenState();
}

class _CertificateScannerScreenState extends State<CertificateScannerScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImage;
  bool _isScanning = false;
  String? _extractedText;
  Map<String, dynamic>? _extractedData;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificate Scanner'),
        backgroundColor: const Color(0xFF0A4D68),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instructions
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
                        'Select or capture a document to extract text using OCR',
                        style: TextStyle(color: Colors.blue[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Image Source Buttons
            if (_selectedImage == null) ...[
              _buildSourceButton(
                icon: Icons.camera_alt,
                label: 'Take Photo',
                onPressed: () => _pickImage(ImageSource.camera),
                color: const Color(0xFF0A4D68),
              ),
              const SizedBox(height: 12),
              _buildSourceButton(
                icon: Icons.photo_library,
                label: 'Choose from Gallery',
                onPressed: () => _pickImage(ImageSource.gallery),
                color: const Color(0xFF088395),
              ),
            ],

            // Selected Image
            if (_selectedImage != null) ...[
              Container(
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _selectedImage!.path,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Image.file(
                        _selectedImage! as dynamic,
                        fit: BoxFit.cover,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isScanning ? null : _scanDocument,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.document_scanner),
                      label: Text(_isScanning ? 'Scanning...' : 'Scan Document'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A4D68),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedImage = null;
                        _extractedText = null;
                        _extractedData = null;
                        _errorMessage = null;
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('New Scan'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Error Message
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[900]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Extracted Data
            if (_extractedData != null && _extractedData!.isNotEmpty) ...[
              const Text(
                'Extracted Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A4D68),
                ),
              ),
              const SizedBox(height: 12),
              ..._extractedData!.entries.map((entry) => _buildDataCard(
                    entry.key,
                    entry.value.toString(),
                  )),
              const SizedBox(height: 24),
            ],

            // Raw Extracted Text
            if (_extractedText != null) ...[
              const Text(
                'Raw Extracted Text',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A4D68),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SelectableText(
                  _extractedText!,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: _isScanning ? null : onPressed,
      icon: Icon(icon, size: 32),
      label: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildDataCard(String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = image;
          _extractedText = null;
          _extractedData = null;
          _errorMessage = null;
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Failed to pick image: $error';
      });
    }
  }

  Future<void> _scanDocument() async {
    if (_selectedImage == null) return;

    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _extractedText = null;
      _extractedData = null;
    });

    try {
      // Perform OCR
      final ocrService = OCRService();
      final result = await ocrService.recognizeText(_selectedImage!.path);
      
      setState(() {
        _extractedText = result['text'] as String;
      });

      // Extract structured data
      final certificateData = dataExtractionService.extractCertificateData(result['text'] as String);
      
      if (certificateData.isEmpty) {
        // Try crew data extraction
        final crewData = dataExtractionService.extractCrewData(result['text'] as String);
        setState(() {
          _extractedData = crewData;
        });
      } else {
        setState(() {
          _extractedData = certificateData;
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Failed to scan document: $error';
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }
}
