// lib/utils/logger.dart

import 'package:flutter/foundation.dart';

class AppLog {
  // High-level: Centralizes diagnostic output and ensures logs are excluded from production binaries.
  static void error(String context, dynamic error, [StackTrace? stack]) {
    // Developer Expectation: 
    // kDebugMode prevents sensitive information from being accessible via logs in release builds.
    if (kDebugMode) {
      debugPrint('--- REPOSITORY ERROR ---');
      debugPrint('Context: $context');
      debugPrint('Details: $error');
      if (stack != null) {
        debugPrint('Stack: $stack');
      }
      debugPrint('------------------------');
    }
  }
}