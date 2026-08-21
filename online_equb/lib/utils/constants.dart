// lib/utils/constants.dart

import 'package:flutter/material.dart';
import '../config/theme.dart';

class AppConstants {
  static String _currentLanguage = 'en';

  // Language codes
  static const String LANG_EN = 'en';
  static const String LANG_AM = 'am';

  // API Configuration
  static const String BASE_URL = 'http://localhost:3000/api/v1';
  static const Duration TIMEOUT = Duration(seconds: 30);

  // Equb Levels Configuration
  static final Map<String, Map<String, dynamic>> levelConfig = {
    'low': {
      'name': 'Low Level',
      'nameAm': 'ዝቅተኛ ደረጃ',
      'price': 100,
      'description': 'Budget-friendly equb for everyone',
      'descriptionAm': 'ለሁሉም የሚስማማ በጀት-친화적 な እቁብ',
      'color': Colors.blue,
      'icon': Icons.trending_down,
      'participants': 50,
    },
    'medium': {
      'name': 'Medium Level',
      'nameAm': 'መካከለኛ ደረጃ',
      'price': 500,
      'description': 'Standard equb with better returns',
      'descriptionAm': 'ተሻላጨ ተመላሾች ያለው ተመሳሳይ እቁብ',
      'color': Colors.orange,
      'icon': Icons.trending_up,
      'participants': 100,
    },
    'high': {
      'name': 'High Level',
      'nameAm': 'ከፍተኛ ደረጃ',
      'price': 1000,
      'description': 'Premium equb with maximum returns',
      'descriptionAm': 'ከፍተኛ ተመላሾች ያለው የሚስተር እቁብ',
      'color': Colors.green,
      'icon': Icons.trending_up,
      'participants': 150,
    },
  };

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
