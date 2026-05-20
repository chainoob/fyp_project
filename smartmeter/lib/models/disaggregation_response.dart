// lib/models/disaggregation_response.dart

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

  factory DisaggregationData.fromJson(Map<String, dynamic> json) {
    final hourlyRaw = json['hourlyUsage'] as Map<String, dynamic>? ?? {};
    final Map<int, double> hourlyParsed = hourlyRaw.map(
      (key, value) => MapEntry(int.parse(key), (value as num).toDouble()),
    );

    final breakdownRaw = (json['breakdown'] ?? json['applianceBreakdown'] ?? {}) as Map<String, dynamic>;
    final Map<String, double> breakdownParsed = breakdownRaw.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );

    final benchmarkRaw = (json['benchmark_breakdown'] ?? json['benchmarkBreakdown'] ?? {}) as Map<String, dynamic>;
    final Map<String, double> benchmarkParsed = benchmarkRaw.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );

    return DisaggregationData(
      userId: json['userId'] as String? ?? json['user_id'] as String? ?? '',
      month: json['month'] as int? ?? 1,
      year: json['year'] as int? ?? 2026,
      estimatedLoad: (json['estimated_load'] as num?)?.toDouble() ?? (json['estimatedLoad'] as num?)?.toDouble() ?? 0.0,
      estimatedCost: (json['estimated_cost'] as num?)?.toDouble() ?? (json['estimatedCost'] as num?)?.toDouble() ?? 0.0,
      carbonFootprint: (json['carbon_footprint'] as num?)?.toDouble() ?? (json['carbonFootprint'] as num?)?.toDouble() ?? 0.0,
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