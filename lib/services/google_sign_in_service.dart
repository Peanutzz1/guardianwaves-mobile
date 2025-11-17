import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GoogleSignInService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      print('Starting Google sign-in flow...');
      
      // Step 1: Trigger the Google sign-in flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        print('User cancelled Google sign-in');
        return {'success': false, 'error': 'Google Sign-In was cancelled'};
      }

      // Step 2: Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Step 3: Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      print('Obtained Google credentials');

      // Step 4: Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;
      
      if (firebaseUser == null) {
        print('Firebase user is null');
        return {'success': false, 'error': 'Failed to authenticate with Firebase'};
      }

      print('Firebase authentication successful for ${firebaseUser.email}');

      // Step 5: Check if user exists in Firestore and get role
      Map<String, dynamic> userData = await _getUserRoleFromFirestore(
        firebaseUser.uid,
        firebaseUser.email!,
      );

      // Step 6: Create user document if it doesn't exist
      String? photoUrl = firebaseUser.photoURL;
      bool requiresOTP = false;
      
      if (userData['exists'] != true) {
        // New user - create account with OTP verification required
        print('Creating new client account for Google user (OTP verification required)...');
        await _createUserDocument(firebaseUser, userData['role'], photoUrl);
        requiresOTP = userData['role'] == 'client';

        // Ensure local state reflects pending verification for new Google users
        userData = {
          'exists': true,
          'role': userData['role'],
          'accountStatus': userData['role'] == 'client'
              ? 'pending-verification'
              : 'active',
          'otpVerified': userData['role'] == 'client' ? false : true,
          'emailVerified': userData['role'] == 'client' ? false : true,
        };
      } else {
        // Fetch existing user data to get photoUrl from Firestore
        final existingUser = await _getExistingUserData(
          firebaseUser.email!,
          userData['role'],
        );
        photoUrl = existingUser['photoUrl'] ?? photoUrl;
        
        // Check if existing user needs OTP verification
        // For existing users, default otpVerified to true (only require OTP if explicitly false or pending-verification)
        final existingAccountStatus = userData['accountStatus'] ?? 'active';
        final existingOtpVerified = userData['otpVerified'];
        // Only require OTP if account is pending verification OR otpVerified is explicitly false
        // Default to true for existing users (matching web app behavior)
        requiresOTP = userData['role'] == 'client' &&
            (existingAccountStatus == 'pending-verification' ||
                existingOtpVerified == false); // Only check for explicit false, not null
      }

      final String accountStatus = userData['accountStatus'] ?? 'active';
      // For existing users, default otpVerified to true (only false if explicitly set)
      // For new users, it will be false from the creation logic above
      final bool otpVerified = userData['otpVerified'] ?? 
          (userData['exists'] == true ? true : false);
      final bool emailVerified =
          userData['emailVerified'] ?? firebaseUser.emailVerified;

      return {
        'success': true,
        'user': {
          'uid': firebaseUser.uid,
          'email': firebaseUser.email,
          'displayName': firebaseUser.displayName,
          'role': userData['role'],
          'username':
              firebaseUser.displayName ?? firebaseUser.email!.split('@')[0],
          'accountStatus': accountStatus,
          'otpVerified': otpVerified,
          'emailVerified': emailVerified,
          if (photoUrl != null) 'photoUrl': photoUrl,
        },
        'requiresOTP': requiresOTP,
      };
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth error: ${e.code} - ${e.message}');
      return {
        'success': false,
        'error': _getFirebaseErrorMessage(e.code)
      };
    } catch (error) {
      print('Google Sign-In error: $error');
      return {
        'success': false,
        'error': 'Google Sign-In failed. Please try again.'
      };
    }
  }

  static Future<Map<String, dynamic>> _getUserRoleFromFirestore(String uid, String email) async {
    try {
      // Check users collection (admin)
      final usersSnapshot = await _db.collection('users').get();
      final adminUser = usersSnapshot.docs.where((doc) => 
        doc.data()['email'] == email
      ).toList();
      
      if (adminUser.isNotEmpty) {
        print('User found in users collection (admin)');
        final adminData = adminUser.first.data();
        return {
          'exists': true,
          'role': adminData['role'] ?? 'admin',
          'accountStatus': adminData['status'] ?? 'active',
          'otpVerified': true,
          'emailVerified': true,
        };
      }

      // Check client collection
      final clientsSnapshot = await _db.collection('client').get();
      final clientUser = clientsSnapshot.docs.where((doc) => 
        doc.data()['email'] == email
      ).toList();
      
      if (clientUser.isNotEmpty) {
        print('User found in client collection');
        final clientData = clientUser.first.data();
        // For existing users, default otpVerified to true if not explicitly set to false
        // This matches web app behavior - only require OTP if explicitly false or pending-verification
        final accountStatus = clientData['accountStatus'] ?? 'active';
        final otpVerified = clientData['otpVerified'];
        // Default to true for existing users (only false if explicitly set)
        final bool finalOtpVerified = (otpVerified == false) ? false : true;
        
        return {
          'exists': true, 
          'role': 'client',
          'accountStatus': accountStatus,
          'otpVerified': finalOtpVerified,
          'emailVerified': clientData['emailVerified'] ?? false,
        };
      }

      // User doesn't exist, return default role
      print('User not found in Firestore, will create with default role');
      return {'exists': false, 'role': 'client'};
    } catch (error) {
      print('Error checking user in Firestore: $error');
      return {'exists': false, 'role': 'client'};
    }
  }

  static Future<void> _createUserDocument(User firebaseUser, String role, String? photoUrl) async {
    try {
      final userDoc = {
        'username': firebaseUser.displayName ?? firebaseUser.email!.split('@')[0],
        'email': firebaseUser.email,
        'role': role,
        'accountStatus': role == 'client' ? 'pending-verification' : 'active', // Require OTP for new client users
        'emailVerified': role == 'admin' ? true : false, // OTP verification will set this to true for clients
        'otpVerified': role == 'admin' ? true : false, // OTP verification required for new client users
        'createdAt': DateTime.now().toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
        'createdBy': 'google-signin',
        'firebaseUid': firebaseUser.uid,
        if (photoUrl != null) 'photoUrl': photoUrl,
      };

      // Create in appropriate collection based on role
      if (role == 'admin') {
        await _db.collection('users').doc(firebaseUser.uid).set(userDoc);
        print('Created admin user document');
      } else {
        await _db.collection('client').doc(firebaseUser.uid).set(userDoc);
        print('Created client user document (OTP verification required)');
      }
    } catch (error) {
      print('Error creating user document: $error');
      // Don't throw error - user is already authenticated
    }
  }

  static Future<Map<String, dynamic>> _getExistingUserData(String email, String role) async {
    try {
      final collection = role == 'admin' ? 'users' : 'client';
      final snapshot = await _db.collection(collection).where('email', isEqualTo: email).get();
      
      if (snapshot.docs.isNotEmpty) {
        final userData = snapshot.docs.first.data();
        return {
          'photoUrl': userData['photoUrl'],
        };
      }
      return {};
    } catch (error) {
      print('Error fetching existing user data: $error');
      return {};
    }
  }

  static String _getFirebaseErrorMessage(String code) {
    switch (code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method.';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again.';
      case 'operation-not-allowed':
        return 'Google Sign-In is not enabled. Please contact support.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No user found with this email.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      print('Google Sign-Out successful');
    } catch (error) {
      print('Google Sign-Out error: $error');
    }
  }
}
