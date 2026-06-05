// lib/models/disaggregation_response.dart6
class DisaggregationResponse {
  final String status;
  final DisaggregationData data;
  final String message;

  DisaggregationResponse({
    required this.status,
    required this.data,
    required this.message,
  });

  factory DisaggregationResponse.fromJson(Map<String, dynamic> json) {
    return DisaggregationResponse(
      status: json['status'] as String,
      data: DisaggregationData.fromJson(json['data'] as Map<String, dynamic>),
      message: json['message'] as String,
    );
  }

  // Serialization mapping for local storage caching
  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'data': data.toJson(),
      'message': message,
    };
  }
}

class DisaggregationData {
  final String userId;
  final int month;
  final int year;
  final double estimatedLoad;
  final double estimatedCost;
  final double carbonFootprint;
  final Map<String, double> breakdown;
  final Map<String, double> benchmarkBreakdown;
  final List<String> anomalies;
  final List<String> recommendations;
  final Map<int, double> hourlyUsage;
  final DateTime timestamp;

  DisaggregationData({
    required this.userId,
    required this.month,
    required this.year,
    required this.estimatedLoad,
    required this.estimatedCost,
    required this.carbonFootprint,
    required this.breakdown,
    required this.benchmarkBreakdown,
    required this.anomalies,
    required this.recommendations,
    required this.hourlyUsage,
    required this.timestamp,
  });

  static double _safeDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  factory DisaggregationData.fromJson(Map<String, dynamic> json) {
    final Map<dynamic, dynamic> hourlyRaw = json['hourlyUsage'] as Map? ?? {};
    final Map<int, double> hourlyParsed = Map<int, double>.from(
      hourlyRaw.map(
        (key, value) => MapEntry(double.tryParse(key.toString())?.toInt() ?? 0, _safeDouble(value)),
      ),
    );

    final Map<dynamic, dynamic> breakdownRaw = (json['breakdown'] ?? json['applianceBreakdown'] ?? {}) as Map;
    final Map<String, double> breakdownParsed = Map<String, double>.from(
      breakdownRaw.map(
        (key, value) => MapEntry(key.toString(), _safeDouble(value)),
      ),
    );

    final Map<dynamic, dynamic> benchmarkRaw = (json['benchmark_breakdown'] ?? json['benchmarkBreakdown'] ?? {}) as Map;
    final Map<String, double> benchmarkParsed = Map<String, double>.from(
      benchmarkRaw.map(
        (key, value) => MapEntry(key.toString(), _safeDouble(value)),
      ),
    );

    return DisaggregationData(
      userId: json['userId'] as String? ?? json['user_id'] as String? ?? '',
      month: json['month'] as int? ?? 1,
      year: json['year'] as int? ?? 2026,
      estimatedLoad: _safeDouble(json['estimated_load'] ?? json['estimatedLoad']),
      estimatedCost: _safeDouble(json['estimated_cost'] ?? json['estimatedCost']),
      carbonFootprint: _safeDouble(json['carbon_footprint'] ?? json['carbonFootprint']),
      breakdown: breakdownParsed,
      benchmarkBreakdown: benchmarkParsed,
      anomalies: List<String>.from(json['anomalies'] as List? ?? []),
      recommendations: List<String>.from(json['recommendations'] as List? ?? []),
      hourlyUsage: hourlyParsed,
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'] as String) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'month': month,
      'year': year,
      'estimated_load': estimatedLoad,
      'estimated_cost': estimatedCost,
      'carbon_footprint': carbonFootprint,
      'breakdown': breakdown,
      'benchmark_breakdown': benchmarkBreakdown,
      'anomalies': anomalies,
      'recommendations': recommendations,
      'hourlyUsage': hourlyUsage.map((key, value) => MapEntry(key.toString(), value)),
      'timestamp': timestamp.toIso8601String(),
    };
  }
}