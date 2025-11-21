import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/custom_auth_service.dart';
import '../services/google_sign_in_service.dart';
import '../services/otp_service.dart';
import '../services/password_reset_service.dart';

class AuthProvider with ChangeNotifier {
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null;

  // Check if current user requires OTP verification
  bool get requiresOTPVerification {
    if (_user == null) return false;
    
    // Google sign-in users never need OTP verification
    final createdBy = _user!['createdBy'];
    if (createdBy == 'google-signin') {
      print('✅ Google sign-in user detected (from user data) - skipping OTP verification');
      return false;
    }
    
    // Additional check: If user is already verified and active, no OTP needed
    final accountStatus = _user!['accountStatus'] ?? 'active';
    final otpVerified = _user!['otpVerified'];
    if (otpVerified == true && accountStatus == 'active') {
      return false;
    }
    
    final role = _user!['role'];
    if (role == 'admin' || role == 'super_admin') {
      return false;
    }
    
    return accountStatus == 'pending-verification' ||
        otpVerified == false ||
        otpVerified == null;
  }
  
  // Async method to check if user is Google sign-in by querying Firestore directly
  Future<bool> isGoogleSignInUser() async {
    if (_user == null || _user!['uid'] == null || _user!['email'] == null) {
      return false;
    }
    
    try {
      // Check if createdBy is already in user data
      if (_user!['createdBy'] == 'google-signin') {
        return true;
      }
      
      // Query Firestore directly to check createdBy
      final role = _user!['role'] ?? 'client';
      final collection = (role == 'admin' || role == 'super_admin') ? 'users' : 'client';
      
      final userRef = FirebaseFirestore.instance
          .collection(collection)
          .doc(_user!['uid']);
      
      final userDoc = await userRef.get();
      
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final createdBy = userData['createdBy'];
        
        if (createdBy == 'google-signin') {
          // Update local user data
          _user = {
            ..._user!,
            'createdBy': 'google-signin',
            'otpVerified': true,
            'emailVerified': true,
            'accountStatus': 'active',
          };
          await _storeUser(_user!);
          notifyListeners();
          print('✅ Google sign-in user detected (from Firestore) - updated user data');
          return true;
        }
      }
    } catch (error) {
      print('❌ Error checking Google sign-in status: $error');
    }
    
    return false;
  }

  AuthProvider() {
    _loadStoredUser();
  }

  Future<void> _loadStoredUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('guardianwaves_user_uid');
      final email = prefs.getString('guardianwaves_user_email');
      final role = prefs.getString('guardianwaves_user_role');
      final username = prefs.getString('guardianwaves_user_username');
      final photoUrl = prefs.getString('guardianwaves_user_photoUrl');
      final createdBy = prefs.getString('guardianwaves_user_createdBy');

      if (uid != null && email != null) {
        // Load basic user data from SharedPreferences
        _user = {
          'uid': uid,
          'email': email,
          'role': role ?? 'client',
          'username': username ?? email,
          if (photoUrl != null) 'photoUrl': photoUrl,
          if (createdBy != null) 'createdBy': createdBy,
        };

        // CRITICAL: Refresh user data from Firestore to get latest OTP verification status
        // This ensures we don't allow access to accounts that haven't verified OTP
        // BUT: For Google sign-in users, don't refresh immediately to avoid overwriting correct values
        print(
          '🔄 Restored user session: $email - refreshing from Firestore to check OTP status',
        );
        print('   - Stored createdBy: $createdBy');
        
        // If this is a Google sign-in user, set verified status immediately
        if (createdBy == 'google-signin') {
          _user = {
            ..._user!,
            'otpVerified': true,
            'emailVerified': true,
            'accountStatus': 'active',
            'createdBy': 'google-signin',
          };
          print('✅ Google sign-in user - setting verified status immediately');
        }
        
        try {
          await refreshUserData();
          print(
            '✅ User data refreshed - OTP status: ${_user?['otpVerified']}, Account status: ${_user?['accountStatus']}, createdBy: ${_user?['createdBy']}',
          );
        } catch (refreshError) {
          print('⚠️ Failed to refresh user data from Firestore: $refreshError');
          print(
            '⚠️ Proceeding with stored data - OTP check will happen in main.dart',
          );
        }

        notifyListeners();
      }
    } catch (error) {
      print('❌ Error loading stored user: $error');
    }
  }

  Future<void> _storeUser(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('guardianwaves_user_uid', userData['uid']);
      await prefs.setString('guardianwaves_user_email', userData['email']);
      await prefs.setString('guardianwaves_user_role', userData['role']);
      await prefs.setString(
        'guardianwaves_user_username',
        userData['username'] ?? userData['email'],
      );
      if (userData['photoUrl'] != null) {
        await prefs.setString(
          'guardianwaves_user_photoUrl',
          userData['photoUrl'],
        );
      }
      // Store createdBy to identify Google sign-in users
      if (userData['createdBy'] != null) {
        await prefs.setString(
          'guardianwaves_user_createdBy',
          userData['createdBy'],
        );
      }
    } catch (error) {
      print('❌ Error storing user: $error');
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  Future<bool> signInWithEmailAndPassword(String email, String password) async {
    try {
      _setLoading(true);
      _setError(null);

      final result = await CustomAuthService.login(email, password);

      if (result['success'] == true) {
        _user = result['user'];
        await _storeUser(result['user']);

        // Check if OTP verification is required
        final requiresOTP = result['requiresOTP'] == true;
        _setLoading(false);

        // Return true even if OTP is required - the UI will handle redirect
        // The requiresOTP flag is stored in user data and can be checked
        return true;
      } else {
        _setError(result['error'] ?? 'Login failed. Please try again.');
        _setLoading(false);
        return false;
      }
    } catch (error) {
      _setLoading(false);
      _setError('An unexpected error occurred.');
      return false;
    }
  }

  Future<bool> registerWithEmailAndPassword(
    String email,
    String password, {
    required String username,
    String? idNumber,
  }) async {
    try {
      _setLoading(true);
      _setError(null);

      final result = await CustomAuthService.register(
        email: email,
        password: password,
        username: username,
        idNumber: idNumber,
      );

      if (result['success'] == true) {
        _user = result['user'];
        await _storeUser(result['user']);

        // Generate and send OTP for new registration (required for all new users)
        // This matches the web app's behavior - OTP is sent during registration
        final requiresOTP = result['requiresOTP'] == true;
        print('🔍 Registration result - requiresOTP: $requiresOTP');

        if (requiresOTP && _user != null && _user!['email'] != null) {
          print('📧 Generating OTP for new sign-up user: ${_user!['email']}');
          try {
            final otpResult = await OTPService.generateAndStoreOTP(
              _user!['email'],
            );
            if (!otpResult['success']) {
              print('⚠️ OTP generation failed: ${otpResult['error']}');
              // Don't fail registration - OTP can be resent from verify-otp screen
              print(
                '⚠️ User can still proceed to OTP screen and request a new code',
              );
            } else {
              print('✅ OTP generated and stored successfully');
              if (otpResult.containsKey('otp')) {
                print('🔐 DEV MODE: OTP code for testing: ${otpResult['otp']}');
                print(
                  '💡 In development mode, you can use this code to verify',
                );
              }
            }
          } catch (otpError) {
            print('⚠️ Error generating OTP: $otpError');
            print(
              '⚠️ Registration succeeded but OTP generation failed - user can still verify',
            );
            // Don't fail registration - OTP can be resent from verify-otp screen
          }
        } else {
          print(
            '⚠️ No OTP required or user data missing - requiresOTP: $requiresOTP, user: ${_user != null}',
          );
        }

        _setLoading(false);
        return true;
      } else {
        final errorMsg =
            result['error'] ?? 'Registration failed. Please try again.';
        print('❌ Registration failed with error: $errorMsg');
        _setError(errorMsg);
        _setLoading(false);
        return false;
      }
    } catch (error) {
      _setLoading(false);
      _setError('An unexpected error occurred during registration.');
      return false;
    }
  }

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      _setLoading(true);
      _setError(null);

      print('Starting Google Sign-In...');
      final result = await GoogleSignInService.signInWithGoogle();

      if (result['success'] == true) {
        _user = result['user'];
        await _storeUser(result['user']);

        final requiresOTP = result['requiresOTP'] == true;
        if (requiresOTP) {
          print(
            'OTP verification required for Google sign-in. User will be redirected to the verification screen.',
          );
        }

        _setLoading(false);
        print('Google Sign-In successful');
        return {
          'success': true,
          'requiresOTP': requiresOTP,
          'user': result['user'],
        };
      } else {
        final errorMessage = result['error'] ?? 'Google Sign-In failed.';
        _setError(errorMessage);
        _setLoading(false);
        return {
          'success': false,
          'error': errorMessage,
        };
      }
    } catch (error) {
      _setLoading(false);
      const errorMessage = 'Google Sign-In failed. Please try again.';
      _setError(errorMessage);
      print('Google Sign-In error: $error');
      return {
        'success': false,
        'error': errorMessage,
      };
    }
  }

  Future<void> signOut() async {
    try {
      // Sign out from Google if needed
      await GoogleSignInService.signOut();

      _user = null;
      _setError(null);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('guardianwaves_user_uid');
      await prefs.remove('guardianwaves_user_email');
      await prefs.remove('guardianwaves_user_role');
      await prefs.remove('guardianwaves_user_username');
      await prefs.remove('guardianwaves_user_photoUrl');
      await prefs.remove('guardianwaves_user_createdBy');
      notifyListeners();
      print('👋 User signed out successfully');
    } catch (e) {
      _setError('Sign out failed.');
      print('❌ Sign out error: $e');
    }
  }

  void clearError() {
    _setError(null);
  }

  // Get current user
  Map<String, dynamic>? get currentUser => _user;

  Future<bool> updateProfile({String? username, String? photoUrl}) async {
    try {
      if (_user == null) {
        _setError('No user logged in');
        return false;
      }

      _setLoading(true);
      _setError(null);

      final result = await CustomAuthService.updateProfile(
        uid: _user!['uid'],
        role: _user!['role'] ?? 'client',
        username: username,
        photoUrl: photoUrl,
      );

      if (result['success'] == true) {
        _user = result['user'];
        await _storeUser(result['user']);
        _setLoading(false);
        return true;
      } else {
        _setError(
          result['error'] ?? 'Profile update failed. Please try again.',
        );
        _setLoading(false);
        return false;
      }
    } catch (error) {
      _setLoading(false);
      _setError('An unexpected error occurred during profile update.');
      return false;
    }
  }

  /// Send OTP code to user's email
  Future<Map<String, dynamic>> sendOTP(String email) async {
    try {
      _setError(null);
      final result = await OTPService.generateAndStoreOTP(email);
      return result;
    } catch (error) {
      print('❌ Error sending OTP: $error');
      return {
        'success': false,
        'error': 'Failed to send OTP. Please try again.',
      };
    }
  }

  /// Verify OTP code
  Future<Map<String, dynamic>> verifyOTP(String email, String code) async {
    try {
      _setError(null);
      final result = await OTPService.verifyOTP(email, code);

      if (result['success'] == true && _user != null) {
        // Update user status in Firestore
        final userRef = FirebaseFirestore.instance
            .collection('client')
            .doc(_user!['uid']);

        await userRef.update({
          'otpVerified': true,
          'emailVerified': true,
          'accountStatus': 'active',
          'otpVerifiedAt': DateTime.now().toIso8601String(),
          'lastUpdated': DateTime.now().toIso8601String(),
        });

        // Delete OTP after successful verification
        await OTPService.deleteOTP(email);

        // Update local user state (preserve createdBy)
        _user = {
          ..._user!,
          'otpVerified': true,
          'emailVerified': true,
          'accountStatus': 'active',
          // Preserve createdBy if it exists
          if (_user!['createdBy'] != null) 'createdBy': _user!['createdBy'],
        };
        await _storeUser(_user!);
        notifyListeners();
      }

      return result;
    } catch (error) {
      print('❌ Error verifying OTP: $error');
      return {
        'success': false,
        'error': 'Failed to verify OTP. Please try again.',
      };
    }
  }

  /// Backward-compatible helper: send verification code using OTP service
  Future<void> sendVerificationCode(String email) async {
    final result = await sendOTP(email);
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to send verification code.');
    }
  }

  /// Backward-compatible helper: verify a code using OTP service
  Future<bool> verifyCode(String email, String code) async {
    final result = await verifyOTP(email, code);
    if (result['success'] == true) {
      return true;
    }
    if (result['error'] != null) {
      throw Exception(result['error']);
    }
    return false;
  }

  /// Reload the latest user snapshot from Firestore
  Future<void> reloadUser() async {
    await refreshUserData();
  }

  /// Send a verification email (reuses OTP channel)
  Future<void> sendEmailVerification() async {
    final email = _user?['email'];
    if (email is! String || email.isEmpty) {
      throw Exception('No email available for verification.');
    }
    await sendVerificationCode(email);
  }

  /// Refresh user data from Firestore
  Future<void> refreshUserData() async {
    if (_user == null || _user!['uid'] == null) {
      return;
    }

    try {
      final role = _user!['role'] ?? 'client';
      final collection = (role == 'admin' || role == 'super_admin')
          ? 'users'
          : 'client';

      // Preserve existing createdBy before refresh
      final existingCreatedBy = _user!['createdBy'];

      final userRef = FirebaseFirestore.instance
          .collection(collection)
          .doc(_user!['uid']);

      final userDoc = await userRef.get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;

        // Admin users don't need OTP verification
        if (role == 'admin' || role == 'super_admin') {
          _user = {
            'uid': userDoc.id,
            'email': userData['email'],
            'role': userData['role'] ?? role,
            'username': userData['username'] ?? userData['email'],
            'accountStatus': 'active', // Admins are always active
            'otpVerified': true, // Admins don't need OTP
            'emailVerified': true, // Admins don't need email verification
            if (userData['photoUrl'] != null) 'photoUrl': userData['photoUrl'],
            // Preserve createdBy - use Firestore value or existing value
            'createdBy': userData['createdBy'] ?? existingCreatedBy,
          };
        } else {
          // Client users - IMPORTANT: For Google sign-in users, ensure they're marked as verified
          final createdBy = userData['createdBy'] ?? existingCreatedBy;
          final isGoogleSignIn = createdBy == 'google-signin';
          
          // If Google sign-in user, force verified status
          final accountStatus = isGoogleSignIn 
              ? 'active' 
              : (userData['accountStatus'] ?? 'active');
          final otpVerified = isGoogleSignIn 
              ? true 
              : (userData['otpVerified'] ?? true);
          
          _user = {
            'uid': userDoc.id,
            'email': userData['email'],
            'role': 'client',
            'username': userData['username'] ?? userData['email'],
            'accountStatus': accountStatus,
            'otpVerified': otpVerified,
            'emailVerified': isGoogleSignIn ? true : (userData['emailVerified'] ?? false),
            if (userData['photoUrl'] != null) 'photoUrl': userData['photoUrl'],
            // Always preserve createdBy
            'createdBy': createdBy,
          };
          
          // If this is a Google sign-in user but Firestore doesn't have the correct status, update it
          if (isGoogleSignIn && (userData['otpVerified'] != true || userData['accountStatus'] != 'active')) {
            print('🔄 Updating Google sign-in user status in Firestore');
            await userRef.update({
              'otpVerified': true,
              'emailVerified': true,
              'accountStatus': 'active',
              'lastUpdated': DateTime.now().toIso8601String(),
            });
          }
        }

        await _storeUser(_user!);
        notifyListeners();
        print('✅ User data refreshed from Firestore - createdBy: ${_user!['createdBy']}');
      } else {
        print(
          '⚠️ User document not found in Firestore - may have been deleted',
        );
      }
    } catch (error) {
      print('❌ Error refreshing user data: $error');
    }
  }

  /// Request password reset code
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      _setLoading(true);
      _setError(null);

      print('🔍 Requesting password reset code for: $email');
      final result = await PasswordResetService.generateAndSendResetCode(email);

      if (result['success'] == true) {
        print('✅ Password reset code sent successfully');
        // In development, log the code for testing
        if (result.containsKey('code')) {
          print('🔐 DEV MODE: Password reset code: ${result['code']}');
        }
      }

      _setLoading(false);
      return result;
    } catch (error) {
      print('❌ Forgot password error: $error');
      _setError(error.toString());
      _setLoading(false);
      return {'success': false, 'error': error.toString()};
    }
  }

  /// Reset password using code
  Future<Map<String, dynamic>> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    try {
      _setLoading(true);
      _setError(null);

      print('🔍 Resetting password with code');
      final result = await PasswordResetService.resetPassword(
        email,
        code,
        newPassword,
      );

      if (result['success'] == true) {
        print('✅ Password reset successful');
      }

      _setLoading(false);
      return result;
    } catch (error) {
      print('❌ Reset password error: $error');
      _setError(error.toString());
      _setLoading(false);
      return {'success': false, 'error': error.toString()};
    }
  }
}
