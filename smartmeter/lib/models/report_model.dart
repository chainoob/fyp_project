class DisaggregationReport {
  final Map<String, double> applianceBreakdown;
  final List<double> hourlyUsage;

  DisaggregationReport({
    required this.applianceBreakdown,
    required this.hourlyUsage,
  });

  factory DisaggregationReport.fromMap(Map<String, dynamic> data) {
    final Map<dynamic, dynamic> rawBreakdown = (data['appliance_breakdown'] is Map)
        ? (data['appliance_breakdown'] as Map)
        : ((data['breakdown'] is Map) ? (data['breakdown'] as Map) : const <dynamic, dynamic>{});
    
    final Map<String, double> parsedBreakdown = {};
    rawBreakdown.forEach((dynamic key, dynamic value) {
      if (value is num) {
        parsedBreakdown[key.toString()] = value.toDouble();
      }
    });

    // 2. String Indexing Fix for Line Chart
    final List<double> parsedHourly = [];
    final Map<dynamic, dynamic> hourlyMap = (data['hourly_usage'] is Map)
        ? (data['hourly_usage'] as Map)
        : ((data['hourlyUsage'] is Map) ? (data['hourlyUsage'] as Map) : const <dynamic, dynamic>{});
        
    for (int i = 0; i < 24; i++) {
      parsedHourly.add((hourlyMap[i.toString()] ?? hourlyMap[i] ?? 0.0).toDouble());
    }

    return DisaggregationReport(
      applianceBreakdown: parsedBreakdown,
      hourlyUsage: parsedHourly,
    );
  }
}
