import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/otp_service.dart';
import '../widgets/main_navigation.dart';
import 'login_screen.dart';

class VerifyOTPScreen extends StatefulWidget {
  final String email;
  
  const VerifyOTPScreen({
    super.key,
    required this.email,
  });

  @override
  State<VerifyOTPScreen> createState() => _VerifyOTPScreenState();
}

class _VerifyOTPScreenState extends State<VerifyOTPScreen> {
  final List<TextEditingController> _otpControllers = 
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  
  bool _loading = false;
  bool _resendLoading = false;
  String? _message;
  String? _error;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  bool _hasSentOTP = false;
  
  // Define brand colors
  static const primaryBlue = Color(0xFF0A4D68);
  static const accentBlue = Color(0xFF088395);
  static const lightBlue = Color(0xFF05BFDB);

  @override
  void initState() {
    super.initState();
    // Auto-send OTP when component mounts (only once)
    // Check if user is already verified and if valid OTP already exists before sending a new one
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_hasSentOTP) {
        _hasSentOTP = true;
        print('📧 Checking if OTP should be sent for: ${widget.email}');
        
        // CRITICAL: Check if user is already verified - don't send OTP for verified accounts
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final user = authProvider.user;
        
        if (user != null) {
          final otpVerified = user['otpVerified'];
          final accountStatus = user['accountStatus'];
          
          // If user is already verified, don't send OTP
          if (otpVerified == true && accountStatus == 'active') {
            print('✅ User is already verified - not sending OTP');
            print('   - otpVerified: $otpVerified');
            print('   - accountStatus: $accountStatus');
            setState(() {
              _message = 'Your account is already verified. Redirecting...';
            });
            // Redirect to dashboard after a short delay
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const MainNavigation()),
                );
              }
            });
            return;
          }
        }
        
        // Check if a valid OTP already exists in Firestore
        final hasValidOTP = await OTPService.hasValidOTP(widget.email);
        
        if (hasValidOTP) {
          print('✅ Valid OTP already exists - not sending duplicate');
          setState(() {
            _message = 'Verification code sent to ${widget.email}. Please check your email.';
          });
          _startCooldown();
        } else {
          print('📧 No valid OTP found - sending new OTP for: ${widget.email}');
          _sendOTP();
        }
      }
    });
    
    // Auto-focus first input on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNodes.isNotEmpty) {
        _focusNodes[0].requestFocus();
      }
    });
    
    // Add listeners to handle backspace on empty fields
    for (int i = 0; i < _focusNodes.length; i++) {
      _focusNodes[i].addListener(() {
        if (_focusNodes[i].hasFocus) {
          // When field gets focus, select all text if it has any
          if (_otpControllers[i].text.isNotEmpty) {
            _otpControllers[i].selection = TextSelection(
              baseOffset: 0,
              extentOffset: _otpControllers[i].text.length,
            );
          }
        }
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // Cooldown timer
  void _startCooldown() {
    setState(() {
      _cooldown = 60; // 60 second cooldown
    });

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_cooldown > 0) {
            _cooldown--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _sendOTP({bool forceResend = false}) async {
    setState(() {
      _resendLoading = true;
      _error = null;
      _message = null;
    });

    try {
      print('📧 Starting OTP generation for: ${widget.email} (forceResend: $forceResend)');
      
      // If forceResend is true (from resend button), delete existing OTP first
      if (forceResend) {
        print('🔄 Force resend requested - deleting existing OTP');
        await OTPService.deleteOTP(widget.email);
      }
      
      final result = await OTPService.generateAndStoreOTP(widget.email);

      print('📧 OTP Service Result: success=${result['success']}');

      if (result['success'] == true) {
        setState(() {
          _message = 'Verification code sent to ${widget.email}. Please check your email.';
        });
        _startCooldown();

        // In development, show the OTP in console for testing
        if (result.containsKey('otp')) {
          print('🔐 DEV MODE: OTP Code: ${result['otp']}');
          print('💡 Copy this code above to verify your account');
        }
      } else {
        final errorMsg = result['error'] ?? 'Failed to send verification code. Please try again.';
        print('❌ OTP generation failed: $errorMsg');

        // In development, if OTP is available, don't treat as complete failure
        if (result.containsKey('otp')) {
          print('🔐 DEV MODE: Email failed but OTP available for testing: ${result['otp']}');
          setState(() {
            _message = '⚠️ Email failed, but you can test with code: ${result['otp']}';
            _error = null; // Clear error so user can proceed
          });
        } else {
          setState(() {
            _error = errorMsg;
          });
        }
      }
    } catch (error) {
      print('❌ Error sending OTP: $error');
      setState(() {
        _error = 'Failed to send verification code: ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _resendLoading = false;
        });
      }
    }
  }

  void _handleInputChange(int index, String value) {
    // Only allow digits
    if (!RegExp(r'^\d*$').hasMatch(value)) {
      // Clear invalid input
      _otpControllers[index].clear();
      return;
    }

    // Only take last character
    if (value.length > 1) {
      value = value.substring(value.length - 1);
    }

    setState(() {
      _otpControllers[index].text = value;
    });

    // Auto-focus next input when a digit is entered
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  void _handlePaste(String pastedData) {
    final cleanedData = pastedData.replaceAll(RegExp(r'[^\d]'), '').substring(0, pastedData.length > 6 ? 6 : pastedData.length);
    
    if (cleanedData.length == 6) {
      for (int i = 0; i < 6; i++) {
        _otpControllers[i].text = cleanedData[i];
      }
      _focusNodes[5].requestFocus();
      // Auto-verify if all digits are filled
      Future.delayed(const Duration(milliseconds: 100), () {
        _verifyOTP();
      });
    }
  }

  Future<void> _verifyOTP() async {
    final code = _otpControllers.map((c) => c.text).join('');

    if (code.length != 6) {
      setState(() {
        _error = 'Please enter the complete 6-digit code.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
      // Verify OTP using AuthProvider (which handles Firestore updates)
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final verifyResult = await authProvider.verifyOTP(widget.email, code);

      if (verifyResult['success'] == true) {
        print('✅ OTP verified successfully');
        
        // Refresh user data to get updated status
        print('🔄 Refreshing user data...');
        await authProvider.refreshUserData();

        setState(() {
          _message = 'Verification successful! Redirecting to dashboard...';
        });

        // Give time for state to update before redirect
        await Future.delayed(const Duration(milliseconds: 1500));
        
        if (mounted) {
          print('🚀 Redirecting to dashboard...');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainNavigation()),
          );
        }
      } else {
        setState(() {
          _error = verifyResult['error'] ?? 'Invalid verification code. Please try again.';
        });
        // Clear OTP on error
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
      }
    } catch (error) {
      print('❌ Error verifying OTP: $error');
      setState(() {
        _error = 'Failed to verify code. Please try again.';
      });
      // Clear OTP on error
      for (var controller in _otpControllers) {
        controller.clear();
      }
      _focusNodes[0].requestFocus();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back Button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        Provider.of<AuthProvider>(context, listen: false).signOut();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Logo
                  Center(
                    child: Container(
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
                  ),
                  const SizedBox(height: 16),
                  
                  // Text
                  const Text(
                    'PHILIPPINE COAST GUARD',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'GUARDIAN WAVES',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Maritime Document Management System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Verification Card
                  Container(
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
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Verify Your Account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enter the verification code sent to your email',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: primaryBlue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Exclusive Access Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.security,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Account Verification',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Email Display
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F8FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.email,
                                size: 32,
                                color: primaryBlue,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Verification code sent to:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.email,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: primaryBlue,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Message
                        if (_message != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Text(
                              _message!,
                              style: const TextStyle(color: Colors.green),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        
                        // Error Message
                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        
                        // OTP Input Fields
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Calculate available width and adjust field size accordingly
                            // Account for any padding/margins (subtract a bit for safety)
                            final availableWidth = constraints.maxWidth - 4.0; // Small buffer
                            final spacing = 6.0; // Reduced spacing between fields
                            final totalSpacing = spacing * 5; // 5 gaps between 6 fields
                            final fieldWidth = ((availableWidth - totalSpacing) / 6).clamp(38.0, 42.0);
                            
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(6, (index) {
                                return SizedBox(
                                  width: fieldWidth,
                                  height: 56, // Fixed height to prevent truncation
                                  child: TextFormField(
                                    controller: _otpControllers[index],
                                    focusNode: _focusNodes[index],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    textAlignVertical: TextAlignVertical.center,
                                    maxLength: 1,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: primaryBlue,
                                      height: 1.2, // Adjust line height for better vertical centering
                                    ),
                                    decoration: InputDecoration(
                                      counterText: "",
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                        vertical: 16, // Increased vertical padding
                                      ),
                                      isDense: false, // Set to false to allow proper padding
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
                                    onChanged: (value) {
                                      // Handle backspace on empty field
                                      if (value.isEmpty && index > 0) {
                                        // Move to previous field when backspace clears current field
                                        Future.microtask(() {
                                          _focusNodes[index - 1].requestFocus();
                                        });
                                      } else {
                                        _handleInputChange(index, value);
                                      }
                                    },
                                    onTap: () {
                                      // Select all text when tapped
                                      _otpControllers[index].selection = TextSelection(
                                        baseOffset: 0,
                                        extentOffset: _otpControllers[index].text.length,
                                      );
                                    },
                                    onEditingComplete: () {
                                      if (index < 5) {
                                        _focusNodes[index + 1].requestFocus();
                                      } else {
                                        // Last field, try to verify
                                        _verifyOTP();
                                      }
                                    },
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        
                        // Verify Button
                        ElevatedButton(
                          onPressed: _loading || _otpControllers.any((c) => c.text.isEmpty)
                              ? null
                              : _verifyOTP,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _otpControllers.every((c) => c.text.isNotEmpty) && !_loading
                                ? primaryBlue
                                : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Text(
                                      'Verify Code',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward, size: 18),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Resend Code Section
                        Container(
                          padding: const EdgeInsets.only(top: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.grey[300]!),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                "Didn't receive the code?",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: (_cooldown > 0 || _resendLoading) 
                                    ? null 
                                    : () => _sendOTP(forceResend: true),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryBlue,
                                  side: BorderSide(color: _cooldown > 0 || _resendLoading ? Colors.grey : primaryBlue),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _cooldown > 0
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.timer, size: 16),
                                          const SizedBox(width: 8),
                                          Text('Resend code in ${_cooldown}s'),
                                        ],
                                      )
                                    : _resendLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A4D68)),
                                            ),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(Icons.refresh, size: 16),
                                              SizedBox(width: 8),
                                              Text('Resend Code'),
                                            ],
                                          ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Cancel Button
                        TextButton(
                          onPressed: () {
                            Provider.of<AuthProvider>(context, listen: false).signOut();
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                            );
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

