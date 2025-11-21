import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/verify_otp_screen.dart';
import 'widgets/main_navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

// Helper function to check user's createdBy from Firestore
Future<Map<String, dynamic>?> _checkUserCreatedBy(String uid, String role) async {
  try {
    final collection = (role == 'admin' || role == 'super_admin') ? 'users' : 'client';
    final userRef = FirebaseFirestore.instance.collection(collection).doc(uid);
    final userDoc = await userRef.get();
    
    if (userDoc.exists) {
      final userData = userDoc.data()!;
      return {
        'createdBy': userData['createdBy'],
        'otpVerified': userData['otpVerified'],
        'accountStatus': userData['accountStatus'],
      };
    }
  } catch (e) {
    print('⚠️ Error checking user createdBy: $e');
  }
  return null;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: MaterialApp(
        title: 'GuardianWaves',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            // First check if user is authenticated
            if (!authProvider.isAuthenticated) {
              return const LoginScreen();
            }
            
            final user = authProvider.user;
            if (user == null || user['uid'] == null) {
              return const LoginScreen();
            }
            
            // CRITICAL: Check createdBy first - if it's Google sign-in, go directly to dashboard
            final createdBy = user['createdBy'];
            if (createdBy == 'google-signin') {
              print('✅ Main.dart: Google sign-in user detected - going directly to dashboard (NO OTP)');
              return const MainNavigation();
            }
            
            // Use FutureBuilder to check Firestore if createdBy is null (for new Google sign-in users)
            if (createdBy == null) {
              return FutureBuilder<Map<String, dynamic>?>(
                future: _checkUserCreatedBy(user['uid'], user['role'] ?? 'client'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    // Show loading while checking - but don't show OTP screen
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  
                  final firestoreCreatedBy = snapshot.data?['createdBy'];
                  final firestoreOtpVerified = snapshot.data?['otpVerified'];
                  final firestoreAccountStatus = snapshot.data?['accountStatus'];
                  
                  // If Google sign-in, refresh auth provider and go to dashboard (NO OTP)
                  if (firestoreCreatedBy == 'google-signin') {
                    print('✅ Main.dart: Google sign-in detected from Firestore - going to dashboard (NO OTP)');
                    // Refresh auth provider asynchronously
                    authProvider.refreshUserData();
                    return const MainNavigation();
                  }
                  
                  // Otherwise, use normal OTP check (only for manual sign-up)
                  final isGoogleSignIn = firestoreCreatedBy == 'google-signin';
                  final isAlreadyVerified = firestoreOtpVerified == true && firestoreAccountStatus == 'active';
                  
                  if (!isGoogleSignIn && !isAlreadyVerified && authProvider.requiresOTPVerification) {
                    final email = user['email'] ?? '';
                    if (email.isNotEmpty) {
                      print('🔒 Main.dart: Manual sign-up user - showing OTP screen');
                      return VerifyOTPScreen(email: email);
                    }
                  }
                  
                  return const MainNavigation();
                },
              );
            }
            
            // CRITICAL: Check if OTP verification is required before allowing access
            // This prevents accounts from being used without OTP verification
            // EXCEPTION: Google sign-in users never need OTP verification
            final otpVerified = user['otpVerified'];
            final accountStatus = user['accountStatus'];
            final isGoogleSignIn = createdBy == 'google-signin';
            final isAlreadyVerified = otpVerified == true && accountStatus == 'active';
            
            print('🔍 Main.dart OTP check:');
            print('   - createdBy: $createdBy');
            print('   - otpVerified: $otpVerified');
            print('   - accountStatus: $accountStatus');
            print('   - isGoogleSignIn: $isGoogleSignIn');
            print('   - isAlreadyVerified: $isAlreadyVerified');
            print('   - requiresOTPVerification: ${authProvider.requiresOTPVerification}');
            
            // Skip OTP for Google sign-in users or already verified users
            if (!isGoogleSignIn && !isAlreadyVerified && authProvider.requiresOTPVerification) {
              final email = user['email'] ?? '';
              if (email.isNotEmpty) {
                print('🔒 OTP verification required - redirecting to verify-otp screen');
                return VerifyOTPScreen(email: email);
              } else {
                // If email is missing, can't proceed - go to login
                print('⚠️ User authenticated but email missing - redirecting to login');
                return const LoginScreen();
              }
            }
            
            print('✅ User verified - allowing access to MainNavigation');
            
            // User is authenticated and OTP is verified - allow access
            return const MainNavigation();
          },
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}