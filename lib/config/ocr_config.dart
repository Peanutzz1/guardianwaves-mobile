// OCR Configuration
// Update this file with your API credentials

class OcrConfig {
  // OCR.space API Configuration
  static const String apiKey = 'K82969111988957'; // Your OCR.space API key
  static const String apiUrl = 'https://api.ocr.space/parse/image';
  
  // OCR Settings
  static const String language = 'eng'; // English
  static const String ocrEngine = '2'; // OCR Engine 2 (highest accuracy)
  static const bool detectOrientation = true;
  static const bool scale = true;
  static const bool overlayRequired = false;
  
  // Image Processing Settings
  static const int maxWidth = 1200;
  static const double compression = 0.8;
  static const String format = 'JPEG';
  
  // Fallback Settings
  static const bool useFallback = true; // Use simulated text if API fails
  static const double fallbackConfidence = 0.5;
}
