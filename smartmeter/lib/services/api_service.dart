// smartmeter/lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String _baseUrl = 'https://ml-backend-i252q36f5a-as.a.run.app/api/v1';

  Future<Map<String, dynamic>> triggerDisaggregation({
    required String userId,
    required List<double> aggregateReadings,
  }) async {
    final Uri url = Uri.parse('$_baseUrl/disaggregate');
    
    // High-level: Serialize local primitives to the exact JSON contract required by Pydantic.
    final Map<String, dynamic> requestBody = {
      'user_id': userId,
      'aggregate_readings': aggregateReadings,
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        
        if (decodedResponse['status'] == 'success') {
          // Developer Expectation: Return data payload directly for model factory mapping.
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
}