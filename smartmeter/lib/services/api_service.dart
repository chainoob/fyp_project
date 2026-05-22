// smartmeter/lib/services/api_service.dart

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ApiService {
  final String _baseUrl = 'https://ml-backend-338592292074.asia-southeast1.run.app';

  Future<Map<String, dynamic>> triggerDisaggregation({
    required String userId,
    required List<double> readings,
  }) async {
    final Uri url = Uri.parse('$_baseUrl/api/v1/disaggregate');
    
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User authorization missing.");
    
    final String? idToken = await user.getIdToken();

    final Map<String, dynamic> requestBody = {
      'userId': userId,
      'aggregateReadings': readings,
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

  Future<void> seedSyntheticReddData(String userId) async {
    final url = Uri.parse('$_baseUrl/api/v1/dev/seed-synthetic-redd');
    
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User authorization missing.");
    final String? idToken = await user.getIdToken();

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'user_id': userId,
      }),
    ).timeout(const Duration(minutes: 2)); // High timeout required for HDF5 extraction and batch writes

    if (response.statusCode != 200) {
      throw Exception('Database seeding pipeline failed: HTTP ${response.statusCode}');
    }
  }
}