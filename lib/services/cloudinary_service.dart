import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CloudinaryService {
  static const String cloudName = 'dqgvmw4u6';
  static const String uploadPreset = 'guardian_waves';
  static const String uploadUrl = 'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';

  /// Upload file to Cloudinary
  /// Returns the secure URL of the uploaded file
  static Future<String> uploadFile(
    File file, {
    String? folder,
    Map<String, String>? tags,
    Function(int progress)? onProgress,
  }) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      
      // Add file
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: file.path.split('/').last,
      );
      request.files.add(multipartFile);
      
      // Add upload preset
      request.fields['upload_preset'] = uploadPreset;
      
      // Add folder if provided
      if (folder != null && folder.isNotEmpty) {
        request.fields['folder'] = folder;
      }
      
      // Add tags if provided
      if (tags != null && tags.isNotEmpty) {
        request.fields['tags'] = tags.values.join(',');
      }

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(response.body);
        if (data['error'] != null) {
          throw Exception(data['error']['message']);
        }
        return data['secure_url'] ?? data['url'];
      } else {
        throw Exception('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('Cloudinary upload error: $e');
      rethrow;
    }
  }

  /// Upload certificate file
  static Future<String> uploadCertificate({
    required File file,
    String? vesselId,
    String? certificateId,
  }) async {
    final folder = vesselId != null
        ? 'guardian-waves/vessel-documents/$vesselId/certificates'
        : 'guardian-waves/vessel-documents/certificates';
    
    return uploadFile(
      file,
      folder: folder,
      tags: {
        'certificate': 'true',
        if (vesselId != null) 'vessel': vesselId,
        if (certificateId != null) 'cert-id': certificateId,
      },
    );
  }

  /// Upload scanned file
  static Future<String> uploadScannedFile({
    required File file,
    String? vesselId,
    String? documentType,
  }) async {
    final folder = vesselId != null
        ? 'guardian-waves/vessel-documents/$vesselId/$documentType'
        : 'guardian-waves/vessel-documents/$documentType';
    
    return uploadFile(
      file,
      folder: folder,
      tags: {
        'scanned': 'true',
        if (vesselId != null) 'vessel': vesselId,
        if (documentType != null) 'document-type': documentType,
      },
    );
  }
}

