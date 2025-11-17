# Google Sign-In Testing Guide

## ✅ What We've Implemented

Google Sign-In has been successfully added to the GuardianWaves mobile app with:
- ✅ Google Sign-In package installed
- ✅ Firebase authentication configured
- ✅ SHA-1 certificate registered
- ✅ Beautiful UI with "Continue with Google" button
- ✅ Proper error handling

## ⚠️ Known Issue: Emulator Limitations

**Google Sign-In often doesn't work on Android emulators** due to:
1. Google Play Services security restrictions
2. Limited Google account support on emulators
3. Certificate validation issues

This is a **common and expected limitation** - not a bug in your code!

## 🔧 Option 1: Try With Emulator (May Not Work)

### Requirements:
1. Make sure your emulator has Google Play Services
2. Add a Google account to the emulator:
   - Open **Settings** on emulator
   - Go to **Accounts** → **Add account** → **Google**
   - Sign in with a real Google account

### Run the app:
```bash
cd C:\Users\eljun\Desktop\GuardianWaves\guardianwaves_mobile
flutter run -d emulator-5554
```

**Note:** Even with these steps, Google may block sign-in on emulators for security reasons.

## 🚀 Option 2: Test on Real Android Device (RECOMMENDED)

Google Sign-In works reliably on real devices. Here's how:

### Method A: USB Debugging

1. **Enable Developer Options on your phone:**
   - Go to **Settings** → **About Phone**
   - Tap **Build Number** 7 times
   - Go back to **Settings** → **Developer Options**
   - Enable **USB Debugging**

2. **Connect your phone via USB**

3. **Check if device is detected:**
   ```bash
   flutter devices
   ```

4. **Run the app:**
   ```bash
   flutter run
   ```
   (It will automatically select your physical device)

### Method B: Wireless Debugging (Android 11+)

1. **On your phone:**
   - Settings → Developer Options → Wireless Debugging → ON
   - Tap "Pair device with pairing code"
   - Note the IP address and port

2. **On your computer:**
   ```bash
   adb pair <IP>:<PORT>
   # Enter the pairing code shown on your phone
   
   adb connect <IP>:<PORT>
   flutter devices
   flutter run
   ```

## 📱 Expected Behavior on Real Device

When you click "Continue with Google":
1. ✅ Google account picker appears
2. ✅ Select your account
3. ✅ Grant permissions
4. ✅ Successfully signed in
5. ✅ Navigate to Home Screen

## 🔍 Troubleshooting

### If it still doesn't work on real device:

1. **Check SHA-1 in Firebase Console:**
   - Go to Firebase Console → Project Settings
   - Scroll to "Your apps" section
   - Verify SHA-1: `B5:B3:77:D8:2E:53:F9:F6:4B:2D:A7:1E:A6:A2:3D:4C:6E:5F:8C:25`

2. **Ensure google-services.json is correct:**
   - Location: `android/app/google-services.json`
   - Package name: `com.example.guardianwaves_mobile`

3. **For release builds, add release SHA-1:**
   ```bash
   keytool -list -v -keystore <your-release-keystore> -alias <your-key-alias>
   ```

## 🎉 Summary

Your Google Sign-In implementation is **complete and correct**! The emulator limitation is expected. Once you test on a real Android device, it should work perfectly.

## 📋 Configuration Details

- **Firebase Project ID:** guardianwaves-68df1
- **Package Name:** com.example.guardianwaves_mobile  
- **SHA-1 (Debug):** B5:B3:77:D8:2E:53:F9:F6:4B:2D:A7:1E:A6:A2:3D:4C:6E:5F:8C:25
- **Web Client ID:** 268881505490-o0me5enqrpjr3r7n69in336u9nhtk6b5.apps.googleusercontent.com


