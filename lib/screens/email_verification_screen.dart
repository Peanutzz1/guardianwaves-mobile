import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool isEmailVerified = false;
  bool canResendEmail = true;
  Timer? timer;
  Timer? cooldownTimer;
  int cooldownSeconds = 0;
  String? errorMessage;

  // Define brand colors (same as other screens)
  static const primaryBlue = Color(0xFF0A4D68);
  static const accentBlue = Color(0xFF088395);
  static const lightBlue = Color(0xFF05BFDB);

  @override
  void initState() {
    super.initState();
    // Check if email is verified when screen loads
    isEmailVerified =
        Provider.of<AuthProvider>(
          context,
          listen: false,
        ).currentUser?['emailVerified'] ==
        true;

    if (!isEmailVerified) {
      // Send verification email automatically
      sendVerificationEmail();

      // Check email verification status every 3 seconds
      timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => checkEmailVerified(),
      );
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> checkEmailVerified() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Call reload() to get the latest user info
    await authProvider.reloadUser();

    setState(() {
      isEmailVerified = authProvider.currentUser?['emailVerified'] == true;
    });

    if (isEmailVerified) {
      timer?.cancel();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    }
  }

  void startCooldownTimer() {
    setState(() {
      canResendEmail = false;
      cooldownSeconds = 60;
      errorMessage = null;
    });

    cooldownTimer?.cancel();
    cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (cooldownSeconds > 0) {
          cooldownSeconds--;
        } else {
          canResendEmail = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> sendVerificationEmail() async {
    if (!canResendEmail) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      await authProvider.sendEmailVerification();
      startCooldownTimer();
      setState(() => errorMessage = null);
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        // If it's not a rate limiting error, allow immediate retry
        if (!e.toString().contains('wait')) {
          canResendEmail = true;
          cooldownSeconds = 0;
        } else {
          // For rate limiting, enforce a longer cooldown
          cooldownSeconds = 300; // 5 minutes
          startCooldownTimer();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isEmailVerified) {
      return const HomeScreen();
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryBlue, accentBlue],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.asset(
                    'assets/waveslogo.png',
                    height: 48,
                    width: 48,
                  ),
                ),
                const SizedBox(height: 32),

                // Verification Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 64,
                        color: accentBlue,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Verify your email',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'We\'ve sent a verification email to your inbox. Please check your email and click the verification link.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
                      ),
                      if (errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: canResendEmail
                            ? sendVerificationEmail
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          canResendEmail
                              ? 'Resend Email'
                              : 'Wait ${cooldownSeconds}s',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          // Sign out and return to login screen
                          Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          ).signOut();
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
