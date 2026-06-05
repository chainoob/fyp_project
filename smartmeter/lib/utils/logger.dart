import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppLog {
  // High-level: Centralizes diagnostic output and transmits errors to Firestore for production monitoring.
  static Future<void> error(String context, dynamic error, [StackTrace? stack]) async {
    // Developer Expectation: Local debug console output during development.
    if (kDebugMode) {
      debugPrint('--- REPOSITORY ERROR ---');
      debugPrint('Context: $context');
      debugPrint('Details: $error');
      if (stack != null) {
        debugPrint('Stack: $stack');
      }
      debugPrint('------------------------');
    }

    // Developer Expectation: Asynchronous transmission of error data to cloud database.
    try {
      await FirebaseFirestore.instance.collection('system_logs').add({
        'context': context,
        'error': error.toString(),
        'stack': stack?.toString(),
        'timestamp': FieldValue.serverTimestamp(),
        'environment': kDebugMode ? 'development' : 'production',
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Cloud logging failure: $e');
      }
    }
  }
}