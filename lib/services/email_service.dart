import 'dart:convert';
import 'package:http/http.dart' as http;

/// Email Service for sending OTP codes via EmailJS API
/// Mirrors the web app's emailService.js functionality
class EmailService {
  // EmailJS API endpoint
  static const String _emailjsApiUrl = 'https://api.emailjs.com/api/v1.0/email/send';
  
  // EmailJS Configuration
  // These should match your web app's environment variables:
  // REACT_APP_EMAILJS_SERVICE_ID
  // REACT_APP_EMAILJS_TEMPLATE_ID
  // REACT_APP_EMAILJS_PUBLIC_KEY
  // 
  // To get these values from your EmailJS account:
  // 1. Go to https://www.emailjs.com/ and sign in
  // 2. Service ID: From Email Services (looks like: service_xxxxxxx)
  // 3. Template ID: From Email Templates (looks like: template_xxxxxxx)
  // 4. Public Key: From Account → General → Public Key (looks like: xxxxxxx_xxxxxxxxxxxx)
  //
  // EmailJS Credentials - matching web app configuration
  static const String _emailjsServiceId = 'service_ikaxb13';
  static const String _emailjsTemplateId = 'template_sztbhol';
  static const String _emailjsPublicKey = 'ZLlrUr2ltcmHuYY0H';
  
  // IMPORTANT: If "Use Private Key (recommended)" is enabled in EmailJS account settings,
  // you need to use the Private Key (accessToken) instead of the Public Key.
  // Get Private Key from: EmailJS Dashboard → Account → General → Private Key
  // If you're using Private Key, set this value and the code will use it automatically
  static const String _emailjsPrivateKey = 'M_NqSUf_YHNz07Uc1N_vV'; // Private Key for REST API authentication
  
  /// Send OTP email using EmailJS API
  /// Returns: {success: bool, error?: string}
  static Future<Map<String, dynamic>> sendOTPEmail(String email, String otpCode) async {
    try {
      print('📧 Attempting to send OTP email via EmailJS to: $email');
      
      // Check if EmailJS is configured
      if (_emailjsServiceId.isEmpty || _emailjsTemplateId.isEmpty || _emailjsPublicKey.isEmpty) {
        print('❌ EmailJS not configured');
        print('⚠️ Please set EMAILJS_SERVICE_ID, EMAILJS_TEMPLATE_ID, and EMAILJS_PUBLIC_KEY');
        return { 
          'success': false, 
          'error': 'Email service not configured. Please contact support.' 
        };
      }

      // Prepare template parameters (matching web app's implementation)
      // EmailJS templates use variables like {{code}}, {{user_email}}, etc.
      final templateParams = {
        // OTP code variables (covers all template variations)
        'code': otpCode,                    // Standard EmailJS OTP template variable (MOST COMMON)
        'otp_code': otpCode,                // Alternative
        'verification_code': otpCode,       // Another alternative
        'otp': otpCode,                     // Simple alternative
        
        // Email variables (EmailJS often uses user_email instead of to_email)
        'to_email': email,                  // Our naming
        'user_email': email,                // EmailJS common naming (IMPORTANT!)
        'email': email,                     // Simple alternative
        'to_name': email.split('@')[0],     // Recipient name
        'user_name': email.split('@')[0],   // EmailJS common naming
        'name': email.split('@')[0],        // Simple alternative
        
        // Optional fields
        'subject': 'Your Guardian Waves Verification Code',
        'message': 'Your Guardian Waves verification code is: $otpCode',
        'from_name': 'Guardian Waves',
        'reply_to': email,
      };

      print('📧 EmailJS template params:');
      print('   service_id: $_emailjsServiceId');
      print('   template_id: $_emailjsTemplateId');
      print('   public_key: ${_emailjsPublicKey.isNotEmpty ? _emailjsPublicKey.substring(0, _emailjsPublicKey.length > 10 ? 10 : _emailjsPublicKey.length) + '...' : '(not set)'}');
      print('   params_keys: ${templateParams.keys.toList()}');

      // Prepare request body for EmailJS API
      // CRITICAL: If "Use Private Key (recommended)" is enabled in EmailJS settings,
      // you MUST use the private key (accessToken) instead of public key (user_id)
      // Check EmailJS Dashboard → Account → Security → "Use Private Key (recommended)"
      final bool usePrivateKey = _emailjsPrivateKey.isNotEmpty;
      
      final requestBody = <String, dynamic>{
        'service_id': _emailjsServiceId,
        'template_id': _emailjsTemplateId,
        'template_params': templateParams,
      };
      
      if (usePrivateKey) {
        // When Private Key is enabled, EmailJS REST API requires BOTH:
        // 1. user_id: Public Key (still required)
        // 2. accessToken: Private Key (for authentication)
        requestBody['user_id'] = _emailjsPublicKey;
        requestBody['accessToken'] = _emailjsPrivateKey;
        print('🔑 Using Private Key authentication (both user_id and accessToken)');
        print('🔑 Public Key (user_id): ${_emailjsPublicKey.substring(0, _emailjsPublicKey.length > 10 ? 10 : _emailjsPublicKey.length)}...');
        print('🔑 Private Key (accessToken): ${_emailjsPrivateKey.substring(0, _emailjsPrivateKey.length > 10 ? 10 : _emailjsPrivateKey.length)}...');
      } else {
        // When Private Key is NOT enabled, use 'user_id' with Public Key only
        requestBody['user_id'] = _emailjsPublicKey;
        print('🔑 Using Public Key (user_id) for authentication');
      }

      print('📡 Sending email request to EmailJS API...');
      print('📡 Request URL: $_emailjsApiUrl');
      print('📡 Request Body: ${jsonEncode(requestBody)}');
      
      // Send HTTP request to EmailJS API
      // Note: EmailJS REST API accepts JSON with service_id, template_id, user_id, and template_params
      // IMPORTANT: For Flutter/mobile apps, you must enable "Allow EmailJS API for non-browser applications"
      // in your EmailJS account: Account → Security → Enable the setting
      final response = await http.post(
        Uri.parse(_emailjsApiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout - email service took too long to respond');
        },
      );

      print('📧 EmailJS API Response Status: ${response.statusCode}');
      print('📧 EmailJS API Response Headers: ${response.headers}');
      print('📧 EmailJS API Response Body (raw): ${response.body}');
      
      // Try to parse and display error details more clearly
      if (response.statusCode != 200) {
        print('❌ EmailJS API Error Details:');
        print('   Status Code: ${response.statusCode}');
        try {
          final errorData = jsonDecode(response.body);
          print('   Error Response: ${jsonEncode(errorData)}');
          if (errorData['text'] != null) {
            print('   Error Text: ${errorData['text']}');
          }
          if (errorData['message'] != null) {
            print('   Error Message: ${errorData['message']}');
          }
          if (errorData['error'] != null) {
            print('   Error: ${errorData['error']}');
          }
        } catch (e) {
          print('   Raw Response: ${response.body}');
        }
      }

      // Handle response - EmailJS returns 200 for success
      if (response.statusCode == 200) {
        print('✅ OTP email sent via EmailJS successfully');
        try {
          final responseData = jsonDecode(response.body);
          return { 
            'success': true, 
            'emailId': responseData['text']?.toString() ?? response.statusCode.toString() 
          };
        } catch (e) {
          print('⚠️ Email sent but failed to parse response: $e');
          return { 'success': true }; // Assume success if status is OK
        }
      } else {
        // Handle error response
        String errorMessage = 'Failed to send email (Status: ${response.statusCode})';
        
        // EmailJS 422 error usually means template variables don't match
        if (response.statusCode == 422) {
          errorMessage = 'Email template configuration error. Please check template variables.';
          print('⚠️ EmailJS 422 Error - This usually means:');
          print('   1. Template variables don\'t match expected names');
          print('   2. Service/Template ID mismatch');
          print('   3. Email service not properly connected');
          print('   4. Missing required template variables');
        }
        
        // EmailJS 403/401 errors might indicate authentication issues
        if (response.statusCode == 403 || response.statusCode == 401) {
          errorMessage = 'EmailJS API authentication failed. Possible causes:\n\n'
              '1. "Use Private Key (recommended)" is enabled → You need to set Private Key in code\n'
              '2. "Allow EmailJS API for non-browser applications" is not enabled\n'
              '3. Invalid Public/Private Key\n\n'
              'Check console logs for detailed error message.';
          print('⚠️ EmailJS 403/401 Error - Authentication failed');
          print('   If "Use Private Key (recommended)" is enabled in EmailJS settings:');
          print('   → You MUST use Private Key (accessToken) instead of Public Key');
          print('   → Get Private Key from: EmailJS Dashboard → Account → General → Private Key');
          print('   → Set _emailjsPrivateKey in email_service.dart');
          print('   If "Use Private Key" is NOT enabled:');
          print('   → Ensure "Allow EmailJS API for non-browser applications" is enabled');
        }
        
        // 400 Bad Request might indicate invalid parameters
        if (response.statusCode == 400) {
          errorMessage = 'Invalid EmailJS API request. Please check Service ID, Template ID, and Public Key.';
          print('⚠️ EmailJS 400 Error - Invalid request parameters');
        }
        
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['text'] != null) {
            errorMessage = errorData['text'].toString();
          } else if (errorData['message'] != null) {
            errorMessage = errorData['message'].toString();
          } else if (errorData['error'] != null) {
            errorMessage = errorData['error'].toString();
          }
          print('❌ EmailJS API Error: $errorMessage');
          print('❌ Error details: ${errorData}');
        } catch (e) {
          print('❌ EmailJS API Error (non-JSON): ${response.body}');
          errorMessage = 'EmailJS API Error: ${response.body}';
        }
        
        return { 
          'success': false, 
          'error': errorMessage 
        };
      }
    } catch (error) {
      print('❌ Error sending OTP email: $error');
      print('❌ Error details: ${error.toString()}');
      
      String errorMessage = 'Failed to send verification email. Please try again.';
      
      if (error.toString().contains('timeout') || error.toString().contains('Timeout')) {
        errorMessage = 'Email service timeout. Please check your internet connection and try again.';
      } else if (error.toString().contains('SocketException') || error.toString().contains('network')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (error.toString().isNotEmpty) {
        errorMessage = 'Error: ${error.toString()}';
      }
      
      return { 
        'success': false, 
        'error': errorMessage 
      };
    }
  }

  /// Send password reset code email using EmailJS API
  /// Returns: {success: bool, error?: string}
  static Future<Map<String, dynamic>> sendPasswordResetCodeEmail(String email, String resetCode) async {
    try {
      print('📧 Attempting to send password reset code email via EmailJS to: $email');
      
      // Check if EmailJS is configured
      if (_emailjsServiceId.isEmpty || _emailjsTemplateId.isEmpty || _emailjsPublicKey.isEmpty) {
        print('❌ EmailJS not configured');
        return { 
          'success': false, 
          'error': 'Email service not configured. Please contact support.' 
        };
      }

      // Prepare template parameters (matching web app's implementation)
      final templateParams = {
        // Reset code variables (covers all template variations)
        'code': resetCode,
        'reset_code': resetCode,
        'verification_code': resetCode,
        'otp_code': resetCode,
        'otp': resetCode,
        
        // Email variables
        'to_email': email,
        'user_email': email,
        'email': email,
        'to_name': email.split('@')[0],
        'user_name': email.split('@')[0],
        'name': email.split('@')[0],
        
        // Optional fields
        'subject': 'Reset Your Guardian Waves Password',
        'message': 'Your password reset code is: $resetCode',
        'from_name': 'Guardian Waves',
      };

      print('📧 EmailJS template params for password reset:');
      print('   service_id: $_emailjsServiceId');
      print('   template_id: $_emailjsTemplateId');
      print('   params_keys: ${templateParams.keys.toList()}');

      // Prepare request body for EmailJS API
      final bool usePrivateKey = _emailjsPrivateKey.isNotEmpty;
      
      final requestBody = <String, dynamic>{
        'service_id': _emailjsServiceId,
        'template_id': _emailjsTemplateId,
        'template_params': templateParams,
      };
      
      if (usePrivateKey) {
        // When Private Key is enabled, EmailJS REST API requires BOTH:
        // 1. user_id: Public Key (still required)
        // 2. accessToken: Private Key (for authentication)
        requestBody['user_id'] = _emailjsPublicKey;
        requestBody['accessToken'] = _emailjsPrivateKey;
        print('🔑 Using Private Key authentication (both user_id and accessToken)');
      } else {
        // When Private Key is NOT enabled, use 'user_id' with Public Key only
        requestBody['user_id'] = _emailjsPublicKey;
        print('🔑 Using Public Key (user_id) for authentication');
      }

      print('📡 Sending password reset email request to EmailJS API...');
      
      // Send HTTP request to EmailJS API
      final response = await http.post(
        Uri.parse(_emailjsApiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout - email service took too long to respond');
        },
      );

      print('📧 EmailJS API Response Status: ${response.statusCode}');
      print('📧 EmailJS API Response Body (raw): ${response.body}');
      
      // Try to parse and display error details more clearly
      if (response.statusCode != 200) {
        print('❌ EmailJS API Error Details:');
        print('   Status Code: ${response.statusCode}');
        try {
          final errorData = jsonDecode(response.body);
          print('   Error Response: ${jsonEncode(errorData)}');
          if (errorData['text'] != null) {
            print('   Error Text: ${errorData['text']}');
          }
          if (errorData['message'] != null) {
            print('   Error Message: ${errorData['message']}');
          }
        } catch (e) {
          print('   Raw Response: ${response.body}');
        }
      }

      // Handle response - EmailJS returns 200 for success
      if (response.statusCode == 200) {
        print('✅ Password reset code email sent via EmailJS successfully');
        try {
          final responseData = jsonDecode(response.body);
          return { 
            'success': true, 
            'emailId': responseData['text']?.toString() ?? response.statusCode.toString() 
          };
        } catch (e) {
          print('⚠️ Email sent but failed to parse response: $e');
          return { 'success': true }; // Assume success if status is OK
        }
      } else {
        // Handle error response
        String errorMessage = 'Failed to send email (Status: ${response.statusCode})';
        
        // EmailJS 422 error usually means template variables don't match
        if (response.statusCode == 422) {
          errorMessage = 'Email template configuration error. Please check template variables.';
        }
        
        // EmailJS 403/401 errors might indicate authentication issues
        if (response.statusCode == 403 || response.statusCode == 401) {
          errorMessage = 'EmailJS API authentication failed. Please check your API keys.';
        }
        
        // 400 Bad Request might indicate invalid parameters
        if (response.statusCode == 400) {
          errorMessage = 'Invalid EmailJS API request. Please check Service ID, Template ID, and Public Key.';
        }
        
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['text'] != null) {
            errorMessage = errorData['text'].toString();
          } else if (errorData['message'] != null) {
            errorMessage = errorData['message'].toString();
          } else if (errorData['error'] != null) {
            errorMessage = errorData['error'].toString();
          }
          print('❌ EmailJS API Error: $errorMessage');
        } catch (e) {
          print('❌ EmailJS API Error (non-JSON): ${response.body}');
          errorMessage = 'EmailJS API Error: ${response.body}';
        }
        
        return { 
          'success': false, 
          'error': errorMessage 
        };
      }
    } catch (error) {
      print('❌ Error sending password reset email: $error');
      print('❌ Error details: ${error.toString()}');
      
      String errorMessage = 'Failed to send password reset email. Please try again.';
      
      if (error.toString().contains('timeout') || error.toString().contains('Timeout')) {
        errorMessage = 'Email service timeout. Please check your internet connection and try again.';
      } else if (error.toString().contains('SocketException') || error.toString().contains('network')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (error.toString().isNotEmpty) {
        errorMessage = 'Error: ${error.toString()}';
      }
      
      return { 
        'success': false, 
        'error': errorMessage 
      };
    }
  }
}

