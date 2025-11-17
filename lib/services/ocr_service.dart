// OCR Service for Flutter
// Provides OCR functionality using HTTP API (OCR.space)

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../config/ocr_config.dart';

class OCRService {
  // Use OCR config
  final String apiKey = OcrConfig.apiKey;
  final String apiUrl = OcrConfig.apiUrl;

  // Process image and extract text
  Future<Map<String, dynamic>> recognizeText(String imagePath) async {
    try {
      print('🔍 Starting OCR recognition with OCR.space...');
      
      // Prepare image for OCR (resize and optimize)
      final base64Image = await _prepareImageForOCR(imagePath);
      
      // Prepare form data
      final request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.fields['apikey'] = apiKey;
      request.fields['base64Image'] = 'data:image/jpeg;base64,$base64Image';
      request.fields['language'] = OcrConfig.language;
      request.fields['isOverlayRequired'] = OcrConfig.overlayRequired.toString();
      request.fields['detectOrientation'] = OcrConfig.detectOrientation.toString();
      request.fields['scale'] = OcrConfig.scale.toString();
      request.fields['OCREngine'] = OcrConfig.ocrEngine;
      
      print('🌐 Sending request to OCR.space API...');
      
      // Make API request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode != 200) {
        throw Exception('OCR API request failed: ${response.statusCode} ${response.reasonPhrase}');
      }
      
      final result = json.decode(responseBody);
      print('📡 OCR API response received');
      
      // Check for errors
      if (result['IsErroredOnProcessing'] == true) {
        final errorMessages = result['ErrorMessage'] ?? ['Unknown error'];
        throw Exception('OCR API error: ${errorMessages.join(', ')}');
      }
      
      if (result['ParsedResults'] == null || result['ParsedResults'].isEmpty) {
        throw Exception('No text detected in the image');
      }
      
      final extractedText = result['ParsedResults'][0]['ParsedText'];
      
      if (extractedText == null || extractedText.trim().isEmpty) {
        throw Exception('No text detected in the image');
      }
      
      print('✅ OCR successful!');
      print('📝 Extracted text length: ${extractedText.length}');
      print('📝 Extracted text preview: ${extractedText.substring(0, extractedText.length > 200 ? 200 : extractedText.length)}...');
      
      return {
        'text': extractedText,
        'confidence': result['ParsedResults'][0]['TextOverlay'] != null ? 0.9 : 0.8,
      };
      
    } catch (error) {
      print('❌ OCR recognition error: $error');
      
      // Fallback to simulated OCR if API fails
      if (OcrConfig.useFallback) {
        print('⚠️ API failed, using fallback simulated OCR...');
        return getFallbackText();
      } else {
        rethrow;
      }
    }
  }

  // Prepare image for OCR by resizing and compressing
  Future<String> _prepareImageForOCR(String imagePath) async {
    try {
      print('🖼️ Preparing image for OCR: $imagePath');
      
      // Read image file
      final imageBytes = await File(imagePath).readAsBytes();
      
      // Decode image
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }
      
      // Resize if too large
      img.Image? processedImage = originalImage;
      if (originalImage.width > OcrConfig.maxWidth) {
        final ratio = OcrConfig.maxWidth / originalImage.width;
        final newHeight = (originalImage.height * ratio).round();
        processedImage = img.copyResize(
          originalImage,
          width: OcrConfig.maxWidth,
          height: newHeight,
        );
        print('📏 Resized image from ${originalImage.width}x${originalImage.height} to ${processedImage.width}x${processedImage.height}');
      }
      
      // Encode as JPEG with compression
      final jpegBytes = img.encodeJpg(processedImage, quality: (OcrConfig.compression * 100).round());
      final base64Image = base64Encode(jpegBytes);
      
      print('✅ Image prepared successfully');
      return base64Image;
    } catch (error) {
      print('❌ Error preparing image for OCR: $error');
      // Fallback to original image
      final imageBytes = await File(imagePath).readAsBytes();
      return base64Encode(imageBytes);
    }
  }

  // Fallback simulated text for when API fails
  Map<String, dynamic> getFallbackText() {
    final simulatedText = '''
CERTIFICATE OF PUBLIC CONVENIENCE
CPC No. 123456
Issued: 15 March 2023
Valid Until: 15 March 2025
Issuing Authority: MARINA
Certificate Holder: Sample Shipping Company
Vessel Name: MV Sea Guardian
IMO Number: 9876543
    '''.trim();

    print('📝 Using fallback simulated text');
    
    return {
      'text': simulatedText,
      'confidence': 0.5
    };
  }

  // Extract certificate data from text
  Map<String, dynamic> extractCertificateData(String text) {
    try {
      // Extract certificate type
      String? certificateType;
      if (text.contains('PUBLIC CONVENIENCE')) {
        certificateType = 'CERTIFICATE OF PUBLIC CONVENIENCE';
      } else if (text.contains('SAFETY MANAGEMENT')) {
        certificateType = 'SAFETY MANAGEMENT CERTIFICATE';
      } else if (text.contains('DOCUMENT OF COMPLIANCE')) {
        certificateType = 'DOCUMENT OF COMPLIANCE';
      }
      
      // Extract dates
      final issuedMatch = RegExp(r'Issued:\s*(\d{1,2}\s+\w+\s+\d{4})').firstMatch(text);
      final expiryMatch = RegExp(r'(?:Valid Until|Expires|Expiry):\s*(\d{1,2}\s+\w+\s+\d{4})').firstMatch(text);
      
      // Parse dates
      String? dateIssued;
      String? dateExpiry;
      
      if (issuedMatch != null) {
        dateIssued = _parseDate(issuedMatch.group(1)!);
      }
      if (expiryMatch != null) {
        dateExpiry = _parseDate(expiryMatch.group(1)!);
      }
      
      return {
        'certificateType': certificateType,
        'dateIssued': dateIssued,
        'dateExpiry': dateExpiry,
      };
      
    } catch (e) {
      print('Error extracting certificate data: $e');
      return {};
    }
  }
  
  // Parse date from "DD MMM YYYY" format
  String _parseDate(String dateStr) {
    try {
      final months = {
        'january': '01', 'jan': '01',
        'february': '02', 'feb': '02',
        'march': '03', 'mar': '03',
        'april': '04', 'apr': '04',
        'may': '05',
        'june': '06', 'jun': '06',
        'july': '07', 'jul': '07',
        'august': '08', 'aug': '08',
        'september': '09', 'sep': '09',
        'october': '10', 'oct': '10',
        'november': '11', 'nov': '11',
        'december': '12', 'dec': '12',
      };
      
      final parts = dateStr.toLowerCase().split(RegExp(r'\s+'));
      if (parts.length == 3) {
        final day = parts[0].padLeft(2, '0');
        final month = months[parts[1]] ?? '01';
        final year = parts[2];
        
        return '$day/$month/$year';
      }
    } catch (e) {
      print('Error parsing date: $e');
    }
    return '';
  }
}
