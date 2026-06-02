import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'network_state_detector.dart';

class ApiService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ml-backend-338592292074.asia-southeast1.run.app',
  );
  final NetworkStateDetector _detector = NetworkStateDetector();

  // RESTORED: Real-time ML Pipeline invocation
  Future<Map<String, dynamic>> triggerDisaggregation({
    required String userId,
    required List<double> readings,
    required Map<String, double?> manualOverrides,
    required List<String> registeredAppliances,
  }) async {
    final Uri url = Uri.parse('$_baseUrl/api/v1/realtime-disaggregations');
    
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User authorization missing.");
    
    final String? idToken = await user.getIdToken();

    Map<String, double?> networkConstraints = await _detector.evaluateApplianceNetworkStates(registeredAppliances);

    final Map<String, dynamic> requestBody = {
      'userId': userId,
      'aggregateReadings': readings,
      'networkStates': networkConstraints,
      'manualOverrides': manualOverrides,
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        
        if (decodedResponse['status'] == 'success') {
          return decodedResponse['data'] as Map<String, dynamic>;
        } else {
          throw Exception(decodedResponse['message'] ?? 'Backend logic failure');
        }
      } else {
        throw Exception('Server Error: Code ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network Pipeline Exception: $e');
    }
  }

  Future<void> seedSyntheticReddData(String userId, {int? month, int? year}) async {
    final url = Uri.parse('$_baseUrl/api/v1/dev/redd-seeds');
    
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User authorization missing.");
    final String? idToken = await user.getIdToken();

    final now = DateTime.now();

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'userId': userId,
        'month': month ?? now.month,
        'year': year ?? now.year,
      }),
    ).timeout(const Duration(minutes: 2));

    if (response.statusCode != 200) {
      throw Exception('Database seeding pipeline failed: HTTP ${response.statusCode}');
    }
  }
}