import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class CodeVerificationScreen extends StatefulWidget {
  final String email;
  final String phoneNumber;
  const CodeVerificationScreen({
    super.key,
    required this.email,
    required this.phoneNumber,
  });

  @override
  State<CodeVerificationScreen> createState() => _CodeVerificationScreenState();
}

class _CodeVerificationScreenState extends State<CodeVerificationScreen> {
  final List<TextEditingController> codeControllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> focusNodes = List.generate(6, (index) => FocusNode());
  
  bool isVerifying = false;
  bool canResendCode = true;
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
    // Send verification code automatically after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sendVerificationCode();
    });
  }

  @override
  void dispose() {
    for (var controller in codeControllers) {
      controller.dispose();
    }
    for (var node in focusNodes) {
      node.dispose();
    }
    cooldownTimer?.cancel();
    super.dispose();
  }

  void startCooldownTimer() {
    setState(() {
      canResendCode = false;
      cooldownSeconds = 60;
      errorMessage = null;
    });

    cooldownTimer?.cancel();
    cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (cooldownSeconds > 0) {
          cooldownSeconds--;
        } else {
          canResendCode = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> sendVerificationCode() async {
    if (!canResendCode) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    try {
      await authProvider.sendVerificationCode(widget.email);
      startCooldownTimer();
      setState(() => errorMessage = null);
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        // If it's not a rate limiting error, allow immediate retry
        if (!e.toString().contains('wait')) {
          canResendCode = true;
          cooldownSeconds = 0;
        } else {
          // For rate limiting, enforce a longer cooldown
          cooldownSeconds = 300; // 5 minutes
          startCooldownTimer();
        }
      });
    }
  }

  Future<void> verifyCode() async {
    final code = codeControllers.map((c) => c.text).join();
    if (code.length != 6) {
      setState(() => errorMessage = 'Please enter the complete 6-digit code');
      return;
    }

    setState(() {
      isVerifying = true;
      errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.verifyCode(widget.email, code);
      
      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        setState(() => errorMessage = 'Invalid verification code');
      }
    } catch (e) {
      setState(() => errorMessage = e.toString());
    } finally {
      setState(() => isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        Icons.mail_outline_rounded,
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
                        'We\'ve sent a verification code to\n${widget.email}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Code Input Fields
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(6, (index) {
                          return SizedBox(
                            width: 40,
                            child: TextFormField(
                              controller: codeControllers[index],
                              focusNode: focusNodes[index],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              maxLength: 1,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: accentBlue),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: accentBlue, width: 2),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (value) {
                                if (value.isNotEmpty && index < 5) {
                                  focusNodes[index + 1].requestFocus();
                                }
                                if (value.isEmpty && index > 0) {
                                  focusNodes[index - 1].requestFocus();
                                }
                                if (index == 5 && value.isNotEmpty) {
                                  focusNodes[index].unfocus();
                                  verifyCode();
                                }
                              },
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 24),

                      // Error Message
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

                      // Verify Button
                      ElevatedButton(
                        onPressed: isVerifying ? null : verifyCode,
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
                        child: isVerifying
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Verify Code',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Resend Code Button
                      TextButton(
                        onPressed: canResendCode ? sendVerificationCode : null,
                        style: TextButton.styleFrom(
                          foregroundColor: accentBlue,
                        ),
                        child: Text(
                          canResendCode
                              ? 'Resend Code'
                              : 'Resend Code in ${cooldownSeconds}s',
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Cancel Button
                      TextButton(
                        onPressed: () {
                          // Sign out and return to login screen
                          Provider.of<AuthProvider>(context, listen: false).signOut();
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
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
