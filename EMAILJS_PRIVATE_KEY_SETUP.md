# EmailJS Private Key Setup

## ⚠️ CRITICAL: You Have "Use Private Key (recommended)" Enabled

Your EmailJS account has **"Use Private Key (recommended)"** enabled. This means:
- ❌ **Public Key will NOT work** for REST API calls
- ✅ **You MUST use Private Key** (`accessToken`) instead

## Steps to Fix:

1. **Get Your Private Key:**
   - Go to https://www.emailjs.com/
   - Sign in to your account
   - Navigate to **Account** → **General**
   - Find **"Private Key"** (NOT Public Key)
   - Copy the Private Key

2. **Add Private Key to Code:**
   - Open: `lib/services/email_service.dart`
   - Find line 31: `static const String _emailjsPrivateKey = '';`
   - Replace the empty string with your Private Key:
     ```dart
     static const String _emailjsPrivateKey = 'YOUR_PRIVATE_KEY_HERE';
     ```

3. **Save and Test:**
   - Save the file
   - Restart your Flutter app
   - Try sending OTP again
   - The code will automatically use Private Key when it's set

## Example:

```dart
// Before (not working):
static const String _emailjsPrivateKey = '';

// After (working):
static const String _emailjsPrivateKey = 'your_private_key_here';
```

## Important Notes:

- **Never commit Private Key to public repositories!**
- Private Key is sensitive - keep it secure
- If you don't want to use Private Key, you can disable "Use Private Key (recommended)" in EmailJS settings, but Private Key is recommended for security

## Verification:

After adding the Private Key, check console logs:
- You should see: `🔑 Using Private Key (accessToken) for authentication`
- Email should send successfully!

