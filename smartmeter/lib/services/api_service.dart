import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:smartmeter/models/app_model.dart';
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

  Future<ForecastResponse?> getEnergyForecast(String userId, int month, int year) async {
    final Uri url = Uri.parse('$_baseUrl/api/v1/forecasts');
    
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final String? idToken = await user.getIdToken();

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'user_id': userId,
          'target_month': month,
          'target_year': year,
          'days_to_predict': 30,
          // MUST MATCH Python Pydantic key: 'manual_overrides'
          'manual_overrides': {}, 
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        final Map<String, dynamic> payload = decoded.containsKey('data') ? decoded['data'] : decoded;

        return ForecastResponse.fromJson(payload);
      } else {
        // Expose server errors (e.g., 400 Bad Request) instead of returning null
        throw Exception('Server rejected request: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      rethrow; 
    }
  }

  Future<Map<String, dynamic>> identifyAppliance(File imageFile) async {
    final Uri url = Uri.parse('$_baseUrl/api/v1/recognize-appliance');
    
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User authorization missing.");
    final String? idToken = await user.getIdToken();

    final request = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer $idToken'
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    
    final response = await request.send().timeout(const Duration(seconds: 15));
    
    if (response.statusCode == 200) {
      final responseData = await response.stream.bytesToString();
      return json.decode(responseData);
    } else {
      throw Exception("Vision API network failure: Code ${response.statusCode}");
    }
  }
}