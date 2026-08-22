// lib/utils/constants.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';

class AppConstants {
  static String _currentLanguage = 'en';

  // Language codes
  static const String LANG_EN = 'en';
  static const String LANG_AM = 'am';

  // API Configuration
  static String get BASE_URL {
    if (kIsWeb) return 'http://localhost:8080/api/v1';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8080/api/v1';
    } catch (_) {}
    return 'http://localhost:8080/api/v1';
  }
  static const Duration TIMEOUT = Duration(seconds: 30);

  // Equb Levels Configuration with Official Price Ranges
  static final Map<String, Map<String, dynamic>> levelConfig = {
    'low': {
      'name': 'Low Level',
      'nameAm': 'ዝቅተኛ ደረጃ',
      'priceRange': '1,000 – 5,000 ETB / week',
      'priceRangeAm': '1,000 – 5,000 ብር / በሳምንት',
      'price': 5000,
      'description': 'Low Level Equb (1,000 – 5,000 ETB / week)',
      'descriptionAm': 'ዝቅተኛ እቁብ (ከ 1,000 እስከ 5,000 ብር / በሳምንት)',
      'color': Colors.blue,
      'icon': Icons.trending_down,
      'participants': 1000,
    },
    'medium': {
      'name': 'Medium Level',
      'nameAm': 'መካከለኛ ደረጃ',
      'priceRange': '6,000 – 10,000 ETB / week',
      'priceRangeAm': '6,000 – 10,000 ብር / በሳምንት',
      'price': 10000,
      'description': 'Medium Level Equb (6,000 – 10,000 ETB / week)',
      'descriptionAm': 'መካከለኛ እቁብ (ከ 6,000 እስከ 10,000 ብር / በሳምንት)',
      'color': Colors.orange,
      'icon': Icons.trending_up,
      'participants': 1000,
    },
    'high': {
      'name': 'High Level',
      'nameAm': 'ከፍተኛ ደረጃ',
      'priceRange': '11,000 – 20,000 ETB / week',
      'priceRangeAm': '11,000 – 20,000 ብር / በሳምንት',
      'price': 20000,
      'description': 'High Level Equb (11,000 – 20,000 ETB / week)',
      'descriptionAm': 'ከፍተኛ እቁብ (ከ 11,000 እስከ 20,000 ብር / በሳምንት)',
      'color': Colors.green,
      'icon': Icons.trending_up,
      'participants': 1000,
    },
  };

  static String getLevelPriceRange(String level, {bool isAmharic = false}) {
    final key = level.toLowerCase().replaceAll('equb_', '').trim();
    switch (key) {
      case 'low':
        return isAmharic ? '1,000 – 5,000 ብር / በሳምንት' : '1,000 – 5,000 ETB / week';
      case 'medium':
        return isAmharic ? '6,000 – 10,000 ብር / በሳምንት' : '6,000 – 10,000 ETB / week';
      case 'high':
        return isAmharic ? '11,000 – 20,000 ብር / በሳምንት' : '11,000 – 20,000 ETB / week';
      default:
        return isAmharic ? 'በሱፐር አስተዳዳሪ የተቀመጠ ደረጃ' : 'Super Admin Configured Level';
    }
  }

  static String getLevelNetPrize(String level, {bool isAmharic = false}) {
    final key = level.toLowerCase().replaceAll('equb_', '').trim();
    switch (key) {
      case 'low':
        return isAmharic ? 'እስከ 495,000 ብር' : 'Up to 495,000 ETB';
      case 'medium':
        return isAmharic ? 'እስከ 990,000 ብር' : 'Up to 990,000 ETB';
      case 'high':
        return isAmharic ? 'እስከ 1,980,000 ብር' : 'Up to 1,980,000 ETB';
      default:
        return isAmharic ? 'በስሌት የሚወሰን' : 'Calculated per round';
    }
  }

  static String getLevelCapacity(String level, {bool isAmharic = false}) {
    return isAmharic ? '100+ ተሳታፊዎች (አቅም እስከ 1,000 አባላት)' : '100+ Participants (Capacity up to 1,000)';
  }

  // User Roles
  static const String ROLE_SUPER_ADMIN = 'super_admin';
  static const String ROLE_ADMIN = 'admin';
  static const String ROLE_USER = 'user';

  // Status Codes
  static const String STATUS_ACTIVE = 'active';
  static const String STATUS_PENDING = 'pending';
  static const String STATUS_SUSPENDED = 'suspended';
  static const String STATUS_DELETED = 'deleted';

  // Getters
  static String get currentLanguage => _currentLanguage;

  // Methods
  static void setLanguage(String language) {
    _currentLanguage = language;
  }

  static Map<String, dynamic> getLevelInfo(String level) {
    return levelConfig[level] ?? levelConfig['low']!;
  }

  static String getLocalizedString(String key, String value) {
    if (_currentLanguage == LANG_AM) {
      return _amharicStrings[key] ?? value;
    }
    return value;
  }

  // Localized strings
  static final Map<String, String> _amharicStrings = {
    'dashboard': 'መነሻ ገፅ',
    'users': 'ተጠቃሚዎች',
    'admins': 'አስተዳዳሪዎች',
    'login': 'ግባ',
    'logout': 'ውጣ',
    'email': 'ኢሜይል',
    'password': 'ይለፍ ቃል',
    'username': 'ተጠቃሚ ስም',
    'firstName': 'ስም',
    'lastName': 'የቤተሰብ ስም',
    'phoneNumber': 'ስልክ ቁጥር',
    'nationalId': 'ብሔራዊ መታወቂያ',
    'active': 'ንቁ',
    'suspended': 'ታግዷል',
    'pending': 'በመጠባበቅ ላይ',
    'add': 'አክል',
    'edit': 'ያርትዉ',
    'delete': 'ሰርዝ',
    'save': 'ያቁሙ',
    'cancel': 'ሰርዝ',
    'confirm': 'አረጋግጥ',
    'success': 'ተሳካ',
    'error': 'ስህተት',
    'total': 'ጠቅላላ',
    'welcome': 'እንዲያሳዩ ብዙ ደስ ብሎናል',
    'profile': 'ፕሮፋይል',
    'settings': 'ቅንብሮች',
    'language': 'ቋንቋ',
    'search': 'ፈልግ',
    'loading': 'ሊሰሩ ይችላሉ...',
    'noData': 'ምንም ውሂብ የለም',
    'tryAgain': 'እንደገና ይሞክሩ',
    'close': 'ዝጋ',
  };
}

// Text Styles
class AppTextStyles {
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}

// Spacing
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// Border Radius
class AppRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;
  static const double full = 9999;
}
