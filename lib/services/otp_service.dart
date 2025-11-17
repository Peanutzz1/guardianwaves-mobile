import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'email_service.dart';

/// OTP Service for generating, storing, and verifying OTP codes
/// Mirrors the web app's otpService.js functionality
class OTPService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'otp_codes';
  static const int _expirationMinutes = 10;
  static const int _maxAttempts = 5;

  /// Generate a random 6-digit OTP code
  static String _generateOTP() {
    return (100000 + Random().nextInt(900000)).toString();
  }

  /// Generate and store OTP code for a user
  /// Returns: {success: bool, error?: string, otp?: string}
  /// Note: OTP is returned only in debug mode for testing
  static Future<Map<String, dynamic>> generateAndStoreOTP(String email) async {
    try {
      print('🔍 Generating OTP for: $email');
      
      // CRITICAL: Check if a valid OTP already exists to prevent duplicates
      final existingValidOTP = await hasValidOTP(email);
      if (existingValidOTP) {
        print('⚠️ Valid OTP already exists for this email - not generating duplicate');
        print('💡 Use the existing OTP code or wait for it to expire before requesting a new one');
        return { 
          'success': false, 
          'error': 'A verification code was already sent. Please check your email or wait before requesting a new code.' 
        };
      }
      
      // Generate 6-digit OTP
      final otp = _generateOTP();
      
      // Store OTP in Firestore with expiration (10 minutes)
      final now = DateTime.now();
      final expiresAt = now.add(Duration(minutes: _expirationMinutes));
      
      final otpDoc = {
        'email': email.toLowerCase(),
        'code': otp,
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'attempts': 0,
        'verified': false,
      };
      
      // Use email as document ID for easy lookup
      final otpRef = _db.collection(_collection).doc(email.toLowerCase());
      await otpRef.set(otpDoc);
      
      print('✅ OTP stored in Firestore');
      
      // Send OTP via email using EmailJS API (same as web app)
      print('📧 Sending OTP email to: $email');
      final emailResult = await EmailService.sendOTPEmail(email.toLowerCase(), otp);
      
      if (emailResult['success'] == true) {
        print('✅ OTP email sent successfully');
        
        // In debug mode, also return OTP for testing
        const bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
        if (isDebug) {
          print('🔐 DEV MODE: OTP code for testing: $otp');
          return { 'success': true, 'otp': otp };
        }
        
        return { 'success': true };
      } else {
        print('❌ OTP email failed to send: ${emailResult['error']}');
        
        // In debug mode, still return OTP even if email fails (for testing)
        const bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
        if (isDebug) {
          print('🔐 DEV MODE: Email failed, but OTP available for testing: $otp');
          print('⚠️ Note: In production, email must be sent successfully');
          return { 
            'success': false, 
            'error': emailResult['error'] ?? 'Failed to send verification email. Please try resending.',
            'otp': otp 
          };
        }
        
        // Production: Return error but don't expose OTP
        return { 
          'success': false, 
          'error': emailResult['error'] ?? 'Failed to send verification email. Please try resending.'
        };
      }
    } catch (error) {
      print('❌ Error generating OTP: $error');
      
      String errorMessage = 'Failed to generate OTP. Please try again.';
      if (error.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied. Please contact support or check Firestore rules.';
      } else if (error.toString().isNotEmpty) {
        errorMessage = 'Error: ${error.toString()}';
      }
      
      return { 'success': false, 'error': errorMessage };
    }
  }

  /// Verify OTP code for a user
  /// Returns: {success: bool, error?: string}
  static Future<Map<String, dynamic>> verifyOTP(String email, String code) async {
    try {
      print('🔍 Verifying OTP for: $email');
      
      final otpRef = _db.collection(_collection).doc(email.toLowerCase());
      final otpDoc = await otpRef.get();
      
      if (!otpDoc.exists) {
        print('❌ OTP not found');
        return { 'success': false, 'error': 'OTP code not found. Please request a new code.' };
      }
      
      final otpData = otpDoc.data()!;
      
      // Check if already verified
      if (otpData['verified'] == true) {
        print('❌ OTP already used');
        return { 'success': false, 'error': 'This code has already been used. Please request a new code.' };
      }
      
      // Check if expired
      final now = Timestamp.now();
      final expiresAt = otpData['expiresAt'] as Timestamp;
      if (expiresAt.compareTo(now) < 0) {
        print('❌ OTP expired');
        // Delete expired OTP
        await otpRef.delete();
        return { 'success': false, 'error': 'OTP code has expired. Please request a new code.' };
      }
      
      // Check attempts (max 5 attempts)
      final attempts = otpData['attempts'] as int? ?? 0;
      if (attempts >= _maxAttempts) {
        print('❌ Too many attempts');
        await otpRef.delete();
        return { 'success': false, 'error': 'Too many failed attempts. Please request a new code.' };
      }
      
      // Verify code
      if (otpData['code'] != code) {
        // Increment attempts
        await otpRef.update({
          'attempts': attempts + 1,
        });
        
        final remainingAttempts = _maxAttempts - (attempts + 1);
        return { 
          'success': false, 
          'error': 'Invalid code. $remainingAttempts attempt(s) remaining.' 
        };
      }
      
      // Mark as verified
      await otpRef.update({
        'verified': true,
        'verifiedAt': Timestamp.now(),
      });
      
      print('✅ OTP verified successfully');
      return { 'success': true };
    } catch (error) {
      print('❌ Error verifying OTP: $error');
      return { 'success': false, 'error': 'Failed to verify OTP. Please try again.' };
    }
  }

  /// Delete OTP code (after successful verification or timeout)
  static Future<void> deleteOTP(String email) async {
    try {
      final otpRef = _db.collection(_collection).doc(email.toLowerCase());
      await otpRef.delete();
      print('✅ OTP deleted');
    } catch (error) {
      print('❌ Error deleting OTP: $error');
    }
  }

  /// Check if OTP exists and is valid (not expired, not verified)
  static Future<bool> hasValidOTP(String email) async {
    try {
      final otpRef = _db.collection(_collection).doc(email.toLowerCase());
      final otpDoc = await otpRef.get();
      
      if (!otpDoc.exists) {
        return false;
      }
      
      final otpData = otpDoc.data()!;
      
      // Check if already verified
      if (otpData['verified'] == true) {
        return false;
      }
      
      // Check if expired
      final now = Timestamp.now();
      final expiresAt = otpData['expiresAt'] as Timestamp;
      if (expiresAt.compareTo(now) < 0) {
        return false;
      }
      
      return true;
    } catch (error) {
      print('❌ Error checking OTP: $error');
      return false;
    }
  }
}

