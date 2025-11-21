import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/dashboard_screen.dart';
import '../screens/vessels_screen.dart';
import '../screens/documents_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/admin_dashboard_screen.dart';
import '../screens/certificate_scanner_screen.dart';
import '../screens/verify_otp_screen.dart';
import '../providers/auth_provider.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  bool _hasCheckedGoogleSignIn = false;
  bool _isGoogleSignInUser = false;
  
  @override
  void initState() {
    super.initState();
    _checkGoogleSignInStatus();
  }
  
  Future<void> _checkGoogleSignInStatus() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    
    if (user != null && user['uid'] != null && user['email'] != null) {
      // If createdBy is already set, use it
      if (user['createdBy'] == 'google-signin') {
        setState(() {
          _isGoogleSignInUser = true;
          _hasCheckedGoogleSignIn = true;
        });
        return;
      }
      
      // Otherwise, check Firestore
      try {
        final role = user['role'] ?? 'client';
        final collection = (role == 'admin' || role == 'super_admin') ? 'users' : 'client';
        final userRef = FirebaseFirestore.instance
            .collection(collection)
            .doc(user['uid']);
        final userDoc = await userRef.get();
        
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          final createdBy = userData['createdBy'];
          
          if (createdBy == 'google-signin') {
            setState(() {
              _isGoogleSignInUser = true;
              _hasCheckedGoogleSignIn = true;
            });
            // Refresh user data to update auth provider
            await authProvider.refreshUserData();
            print('✅ MainNavigation: Detected Google sign-in user, refreshed auth provider');
          } else {
            setState(() {
              _isGoogleSignInUser = false;
              _hasCheckedGoogleSignIn = true;
            });
          }
        }
      } catch (e) {
        print('⚠️ Error checking Google sign-in status in MainNavigation: $e');
        setState(() {
          _hasCheckedGoogleSignIn = true;
        });
      }
    } else {
      setState(() {
        _hasCheckedGoogleSignIn = true;
      });
    }
  }
  int _currentIndex = 0;

  bool _isAdmin(AuthProvider authProvider) {
    final role = authProvider.user?['role'];
    return role == 'admin' || role == 'super_admin';
  }

  List<Widget> _buildScreens(AuthProvider authProvider) {
    final isAdmin = _isAdmin(authProvider);
    
    if (isAdmin) {
      return [
        const AdminDashboardScreen(),
        const VesselsScreen(),
        const DocumentsScreen(),
        const ProfileScreen(),
      ];
    }
    
    return [
      const DashboardScreen(),
      const VesselsScreen(),
      const DocumentsScreen(),
      const ProfileScreen(),
    ];
  }

  List<NavigationDestination> _buildDestinations(AuthProvider authProvider) {
    final isAdmin = _isAdmin(authProvider);
    
    if (isAdmin) {
      return const [
        NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
        NavigationDestination(
          icon: Icon(Icons.sailing_outlined),
          selectedIcon: Icon(Icons.sailing),
          label: 'Vessels',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: 'Documents',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ];
    }
    
    return const [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Dashboard',
      ),
      NavigationDestination(
        icon: Icon(Icons.sailing_outlined),
        selectedIcon: Icon(Icons.sailing),
        label: 'Vessels',
      ),
      NavigationDestination(
        icon: Icon(Icons.folder_outlined),
        selectedIcon: Icon(Icons.folder),
        label: 'Documents',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // SAFETY GUARD: Check if OTP verification is required
        // This prevents access even if main.dart check is bypassed
        // EXCEPTION: Google sign-in users never need OTP verification
        final user = authProvider.user;
        final createdBy = user?['createdBy'];
        final otpVerified = user?['otpVerified'];
        final accountStatus = user?['accountStatus'];
        
        // Use the checked Google sign-in status from initState
        final isGoogleSignIn = _isGoogleSignInUser || createdBy == 'google-signin';
        final isAlreadyVerified = otpVerified == true && accountStatus == 'active';
        
        print('🔍 MainNavigation OTP check:');
        print('   - createdBy: $createdBy');
        print('   - _isGoogleSignInUser: $_isGoogleSignInUser');
        print('   - otpVerified: $otpVerified');
        print('   - accountStatus: $accountStatus');
        print('   - isGoogleSignIn: $isGoogleSignIn');
        print('   - isAlreadyVerified: $isAlreadyVerified');
        print('   - requiresOTPVerification: ${authProvider.requiresOTPVerification}');
        
        // Skip OTP for Google sign-in users or already verified users
        if (!isGoogleSignIn && !isAlreadyVerified && authProvider.requiresOTPVerification) {
          final email = authProvider.user?['email'] ?? '';
          if (email.isNotEmpty) {
            print('🔒 MainNavigation: OTP verification required - redirecting to verify-otp');
            // Return OTP screen instead of main navigation
            return VerifyOTPScreen(email: email);
          } else {
            // If email is missing, show error
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Authentication Error',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('Please log in again'),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        authProvider.signOut();
                      },
                      child: const Text('Go to Login'),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        
        final screens = _buildScreens(authProvider);
        
        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: _buildDestinations(authProvider),
          ),
        );
      },
    );
  }
}