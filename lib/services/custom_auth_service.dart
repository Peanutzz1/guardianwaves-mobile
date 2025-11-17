import 'package:cloud_firestore/cloud_firestore.dart';

class CustomAuthService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      print('🔐 Attempting login for: $email');
      
      // First check admin accounts in 'users' collection
      final usersSnapshot = await _db.collection('users').get();
      final adminUser = usersSnapshot.docs.where((doc) {
        final data = doc.data();
        // Check if it's an admin account (either has role='admin' or is in users collection without role='client')
        final isAdmin = data['role'] == 'admin' || (!data.containsKey('role') && !data.containsKey('accountStatus'));
        return data['email'] == email && data['password'] == password && isAdmin;
      }).toList();
      
      if (adminUser.isNotEmpty) {
        final userDoc = adminUser.first;
        final userData = userDoc.data();
        print('✅ Admin login successful');
        return {
          'success': true,
          'user': {
            'uid': userDoc.id,
            'email': userData['email'],
            'role': userData['role'] ?? 'admin', // Default to admin if role is missing
            'username': userData['username'] ?? userData['email'],
            'accountStatus': 'active',
            'otpVerified': true,
            'emailVerified': true,
            if (userData['photoUrl'] != null) 'photoUrl': userData['photoUrl'],
          }
        };
      }
      
      // Then check client accounts in 'client' collection
      final clientsSnapshot = await _db.collection('client').get();
      final clientUser = clientsSnapshot.docs.where((doc) {
        final data = doc.data();
        // Allow login if accountStatus is 'active' or if accountStatus is missing (default to active)
        // Also allow 'pending-verification' status for users in OTP verification flow
        final isValidStatus = data['accountStatus'] == 'active' || 
                             data['accountStatus'] == 'pending-verification' ||
                             !data.containsKey('accountStatus');
        return data['email'] == email && data['password'] == password && isValidStatus;
      }).toList();
      
      if (clientUser.isNotEmpty) {
        final userDoc = clientUser.first;
        final userData = userDoc.data();
        final accountStatus = userData['accountStatus'] ?? 'active';
        final otpVerified = userData['otpVerified'] ?? true; // Default to true for existing users
        
        // Check if OTP verification is required
        final requiresOTP = accountStatus == 'pending-verification' || 
                           otpVerified == false ||
                           otpVerified == null;
        
        print('✅ Client login successful');
        print('🔍 Account status: $accountStatus, OTP Verified: $otpVerified, Requires OTP: $requiresOTP');
        
        return {
          'success': true,
          'user': {
            'uid': userDoc.id,
            'email': userData['email'],
            'role': 'client',
            'username': userData['username'],
            'accountStatus': accountStatus,
            'otpVerified': otpVerified,
            'emailVerified': userData['emailVerified'] ?? false,
            if (userData['photoUrl'] != null) 'photoUrl': userData['photoUrl'],
          },
          'requiresOTP': requiresOTP,
        };
      }
      
      print('❌ Login failed: Invalid credentials');
      return {'success': false, 'error': 'Invalid email or password'};
    } catch (error) {
      print('❌ Login error: $error');
      return {'success': false, 'error': 'Login failed. Please try again.'};
    }
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String username,
    String? idNumber,
  }) async {
    try {
      print('👤 Attempting registration for: $email');
      
      // Check if email already exists in either collection
      final usersSnapshot = await _db.collection('users').get();
      final clientsSnapshot = await _db.collection('client').get();
      
      final existingUser = usersSnapshot.docs.any((doc) => doc.data()['email'] == email);
      final existingClient = clientsSnapshot.docs.any((doc) => doc.data()['email'] == email);
      
      if (existingUser || existingClient) {
        print('❌ Registration failed: Email already exists');
        return {'success': false, 'error': 'Email address is already registered'};
      }
      
      // Create client account in 'client' collection with OTP verification required
      final clientDoc = {
        'username': username,
        'password': password,
        'email': email,
        'role': 'client',
        'idNumber': idNumber ?? '',
        'accountStatus': 'pending-verification', // Require OTP verification before activation
        'emailVerified': false, // OTP verification will set this to true
        'otpVerified': false, // OTP verification required for new sign-up users
        'createdAt': DateTime.now().toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
        'createdBy': 'self-registration'
      };
      
      // Use timestamp for unique ID
      final clientId = 'client_${DateTime.now().millisecondsSinceEpoch}';
      await _db.collection('client').doc(clientId).set(clientDoc);
      
      print('✅ Client account created successfully (OTP verification required)');
      
      // Note: OTP generation should be handled by the calling code (AuthProvider)
      // This allows the UI to show loading states and handle errors properly
      
      return {
        'success': true,
        'user': {
          'uid': clientId,
          'email': email,
          'role': 'client',
          'username': username,
          'accountStatus': 'pending-verification',
          'otpVerified': false,
          'emailVerified': false,
        },
        'requiresOTP': true, // Flag to indicate OTP verification is needed
      };
    } catch (error) {
      print('❌ Registration error: $error');
      print('❌ Registration error details: ${error.toString()}');
      
      // Provide more specific error messages
      String errorMessage = 'Registration failed. Please try again.';
      
      if (error.toString().contains('permission-denied') || 
          error.toString().contains('PERMISSION_DENIED')) {
        errorMessage = 'Permission denied. Please check Firestore rules or contact support.';
      } else if (error.toString().contains('network') || 
                 error.toString().contains('Network')) {
        errorMessage = 'Network error. Please check your internet connection and try again.';
      } else if (error.toString().contains('already exists') || 
                 error.toString().contains('already registered')) {
        errorMessage = 'Email address is already registered.';
      } else if (error.toString().isNotEmpty) {
        // Try to extract a more specific error message
        errorMessage = error.toString().contains('error') 
            ? error.toString() 
            : 'Registration failed: ${error.toString()}';
      }
      
      return {'success': false, 'error': errorMessage};
    }
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String uid,
    required String role,
    String? username,
    String? photoUrl,
  }) async {
    try {
      print('👤 Attempting profile update for: $uid');
      
      // Determine which collection to update based on role
      final collection = role == 'admin' || role == 'super_admin' ? 'users' : 'client';
      
      final updateData = <String, dynamic>{
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      if (username != null && username.isNotEmpty) {
        updateData['username'] = username;
      }
      
      if (photoUrl != null && photoUrl.isNotEmpty) {
        updateData['photoUrl'] = photoUrl;
      }
      
      await _db.collection(collection).doc(uid).update(updateData);
      
      // Get updated user data
      final userDoc = await _db.collection(collection).doc(uid).get();
      final userData = userDoc.data()!;
      
      print('✅ Profile updated successfully');
      return {
        'success': true,
        'user': {
          'uid': uid,
          'email': userData['email'],
          'role': role,
          'username': userData['username'] ?? userData['email'],
          'photoUrl': userData['photoUrl'],
        }
      };
    } catch (error) {
      print('❌ Profile update error: $error');
      return {'success': false, 'error': 'Profile update failed. Please try again.'};
    }
  }
}
