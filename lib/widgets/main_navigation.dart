import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
        if (authProvider.requiresOTPVerification) {
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