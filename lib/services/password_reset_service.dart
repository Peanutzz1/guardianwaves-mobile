import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'email_service.dart';

/// Password Reset Service for generating, storing, and verifying password reset codes
/// Mirrors the web app's passwordResetService.js functionality
class PasswordResetService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'password_reset_codes';
  static const int _expirationMinutes = 10;
  static const int _maxAttempts = 5;

  /// Generate a random 6-digit reset code
  static String _generateResetCode() {
    return (100000 + Random().nextInt(900000)).toString();
  }

  /// Generate and send password reset code to user's email
  /// Returns: {success: bool, error?: string, code?: string, message?: string}
  static Future<Map<String, dynamic>> generateAndSendResetCode(String email) async {
    try {
      print('🔍 Generating password reset code for: $email');
      
      final normalizedEmail = email.toLowerCase().trim();
      
      // Check if user exists in database
      // Check in 'client' collection
      final clientsSnapshot = await _db.collection('client').get();
      final clientUser = clientsSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['email'] != null && 
               data['email'].toString().toLowerCase().trim() == normalizedEmail;
      }).toList();
      
      // Check in 'users' collection (admin)
      final usersSnapshot = await _db.collection('users').get();
      final adminUser = usersSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['email'] != null && 
               data['email'].toString().toLowerCase().trim() == normalizedEmail;
      }).toList();
      
      // Check in 'super_admins' collection
      final superAdminsSnapshot = await _db.collection('super_admins').get();
      final superAdminUser = superAdminsSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['email'] != null && 
               data['email'].toString().toLowerCase().trim() == normalizedEmail;
      }).toList();
      
      // If user doesn't exist, don't reveal that (security best practice)
      if (clientUser.isEmpty && adminUser.isEmpty && superAdminUser.isEmpty) {
        // Return success to prevent email enumeration attacks
        print('⚠️ User not found, but returning success for security');
        return { 
          'success': true, 
          'message': 'If an account with that email exists, a password reset code has been sent.' 
        };
      }
      
      // Generate 6-digit reset code
      final resetCode = _generateResetCode();
      
      // Store reset code in Firestore with expiration (10 minutes)
      final now = DateTime.now();
      final expiresAt = now.add(Duration(minutes: _expirationMinutes));
      
      final resetCodeDoc = {
        'email': normalizedEmail,
        'code': resetCode,
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'used': false,
        'attempts': 0,
      };
      
      // Use email as document ID for easy lookup
      final codeRef = _db.collection(_collection).doc(normalizedEmail);
      await codeRef.set(resetCodeDoc);
      
      print('✅ Password reset code stored in Firestore');
      
      // Send reset code email
      print('📧 Sending password reset email to: $email');
      final emailResult = await EmailService.sendPasswordResetCodeEmail(normalizedEmail, resetCode);
      
      if (emailResult['success'] == true) {
        print('✅ Password reset email sent successfully');
        
        // In debug mode, also return code for testing
        const bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
        if (isDebug) {
          print('🔐 DEV MODE: Password reset code for testing: $resetCode');
          return { 
            'success': true, 
            'message': 'Password reset code sent successfully.',
            'code': resetCode // Only in dev mode
          };
        }
        
        return { 
          'success': true, 
          'message': 'If an account with that email exists, a password reset code has been sent.' 
        };
      } else {
        print('❌ Password reset email failed to send: ${emailResult['error']}');
        
        // In debug mode, still return code even if email fails (for testing)
        const bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
        if (isDebug) {
          print('🔐 DEV MODE: Email failed, but reset code available for testing: $resetCode');
          return { 
            'success': false, 
            'error': emailResult['error'] ?? 'Failed to send password reset email. Please try again.',
            'code': resetCode 
          };
        }
        
        return { 
          'success': false, 
          'error': emailResult['error'] ?? 'Failed to send password reset email. Please try again.' 
        };
      }
    } catch (error) {
      print('❌ Error generating password reset code: $error');
      
      String errorMessage = 'Failed to process password reset request. Please try again.';
      if (error.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied. Please contact support or check Firestore rules.';
      } else if (error.toString().isNotEmpty) {
        errorMessage = 'Error: ${error.toString()}';
      }
      
      return { 'success': false, 'error': errorMessage };
    }
  }

  /// Verify password reset code
  /// Returns: {success: bool, error?: string}
  static Future<Map<String, dynamic>> verifyResetCode(String email, String code) async {
    try {
      print('🔍 Verifying password reset code for: $email');
      
      if (code.isEmpty || code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
        return { 'success': false, 'error': 'Invalid reset code format. Please enter a 6-digit code.' };
      }
      
      final normalizedEmail = email.toLowerCase().trim();
      final codeRef = _db.collection(_collection).doc(normalizedEmail);
      final codeDoc = await codeRef.get();
      
      if (!codeDoc.exists) {
        print('❌ Reset code not found');
        return { 'success': false, 'error': 'Reset code not found. Please request a new one.' };
      }
      
      final codeData = codeDoc.data()!;
      
      // Check if already used
      if (codeData['used'] == true) {
        print('❌ Reset code already used');
        return { 'success': false, 'error': 'This code has already been used. Please request a new one.' };
      }
      
      // Check if expired
      final now = Timestamp.now();
      final expiresAt = codeData['expiresAt'] as Timestamp;
      if (expiresAt.compareTo(now) < 0) {
        print('❌ Reset code expired');
        // Delete expired code
        await codeRef.delete();
        return { 'success': false, 'error': 'Reset code has expired. Please request a new one.' };
      }
      
      // Check attempts (max 5 attempts)
      final attempts = codeData['attempts'] as int? ?? 0;
      if (attempts >= _maxAttempts) {
        print('❌ Too many attempts with this code');
        await codeRef.delete();
        return { 'success': false, 'error': 'Too many failed attempts. Please request a new code.' };
      }
      
      // Verify code
      if (codeData['code'] != code) {
        // Increment attempts
        await codeRef.update({
          'attempts': attempts + 1,
        });
        
        final remainingAttempts = _maxAttempts - (attempts + 1);
        return { 
          'success': false, 
          'error': 'Invalid code. $remainingAttempts attempt(s) remaining.' 
        };
      }
      
      print('✅ Reset code verified successfully');
      return { 'success': true };
    } catch (error) {
      print('❌ Error verifying reset code: $error');
      return { 'success': false, 'error': 'Failed to verify reset code. Please try again.' };
    }
  }

  /// Reset password using code
  /// Returns: {success: bool, error?: string}
  static Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) async {
    try {
      print('🔍 Resetting password with code');
      
      final normalizedEmail = email.toLowerCase().trim();
      
      // Verify code first
      final verifyResult = await verifyResetCode(normalizedEmail, code);
      if (verifyResult['success'] != true) {
        return verifyResult;
      }
      
      // Get the code document
      final codeRef = _db.collection(_collection).doc(normalizedEmail);
      final codeDoc = await codeRef.get();
      
      if (!codeDoc.exists) {
        return { 'success': false, 'error': 'Invalid reset code.' };
      }
      
      // Find user in database and update password
      // Check in 'client' collection
      final clientsSnapshot = await _db.collection('client').get();
      final clientUser = clientsSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['email'] != null && 
               data['email'].toString().toLowerCase().trim() == normalizedEmail;
      }).toList();
      
      // Check in 'users' collection (admin)
      final usersSnapshot = await _db.collection('users').get();
      final adminUser = usersSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['email'] != null && 
               data['email'].toString().toLowerCase().trim() == normalizedEmail;
      }).toList();
      
      // Check in 'super_admins' collection
      final superAdminsSnapshot = await _db.collection('super_admins').get();
      final superAdminUser = superAdminsSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['email'] != null && 
               data['email'].toString().toLowerCase().trim() == normalizedEmail;
      }).toList();
      
      if (clientUser.isNotEmpty) {
        // Update client password
        await _db.collection('client').doc(clientUser.first.id).update({
          'password': newPassword,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        print('✅ Client password updated');
      } else if (adminUser.isNotEmpty) {
        // Update admin password
        await _db.collection('users').doc(adminUser.first.id).update({
          'password': newPassword,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        print('✅ Admin password updated');
      } else if (superAdminUser.isNotEmpty) {
        // Update super admin password
        await _db.collection('super_admins').doc(superAdminUser.first.id).update({
          'password': newPassword,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        print('✅ Super Admin password updated');
      } else {
        return { 'success': false, 'error': 'User not found.' };
      }
      
      // Mark code as used
      await codeRef.update({
        'used': true,
        'usedAt': Timestamp.now(),
      });
      
      // Delete the code after successful use
      await codeRef.delete();
      
      print('✅ Password reset successful');
      return { 'success': true };
    } catch (error) {
      print('❌ Error resetting password: $error');
      return { 'success': false, 'error': 'Failed to reset password. Please try again.' };
    }
  }
}

