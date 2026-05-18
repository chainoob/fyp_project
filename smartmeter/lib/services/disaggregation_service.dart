// lib/services/disaggregation_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/disaggregation_response.dart'; // Import the model file

class DisaggregationService {
  static const String _baseUrl = 'https://ml-backend-338592292074.asia-southeast1.run.app';
  final http.Client _client;

  DisaggregationService({http.Client? client}) : _client = client ?? http.Client();

  Future<DisaggregationResponse> fetchDisaggregation({
    required List<double> aggregateReadings,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Auth Pipeline Failure: Session context is null.');
    }

    // Forces signature re-evaluation if the local token window has decayed (60 min)
    final String? idToken = await user.getIdToken(true); 
    if (idToken == null) {
      throw Exception('Auth Pipeline Failure: Failed to resolve token signature.');
    }

    final Uri url = Uri.parse('$_baseUrl/api/v1/disaggregate');
    
    final http.Response response = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'user_id': user.uid,
        'aggregate_readings': aggregateReadings,
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      return DisaggregationResponse.fromJson(responseData);
    }
    
    throw Exception('Transport Error [${response.statusCode}]: ${response.body}');
  }
}