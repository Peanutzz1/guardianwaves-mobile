import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
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
            
            // CRITICAL: Check if OTP verification is required before allowing access
            // This prevents accounts from being used without OTP verification
            if (authProvider.requiresOTPVerification) {
              final email = authProvider.user?['email'] ?? '';
              if (email.isNotEmpty) {
                print('🔒 OTP verification required - redirecting to verify-otp screen');
                return VerifyOTPScreen(email: email);
              } else {
                // If email is missing, can't proceed - go to login
                print('⚠️ User authenticated but email missing - redirecting to login');
                return const LoginScreen();
              }
            }
            
            // User is authenticated and OTP is verified - allow access
            return const MainNavigation();
          },
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}