import 'package:cloud_firestore/cloud_firestore.dart';

// --- USER MODEL ---
class Users {
  final String uid;
  final String name;
  final String email;
  final String role; // 'student' or 'staff'
  final String? studentId;
  final String? dormBlock;
  final String? department;
  final String? photoUrl;

  const Users({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.studentId,
    this.dormBlock,
    this.department,
    this.photoUrl
  });

  factory Users.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Users(
      uid: doc.id,
      name: data['displayName'] ?? 'Unknown',
      email: data['email'] ?? '',
      role: data['role'] ?? 'student',
      studentId: data['studentId'],
      dormBlock: data['dormBlock'],
      department: data['department'],
      photoUrl: data['photoUrl']
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': name,
      'email': email,
      'role': role,
      'studentId': studentId,
      'dormBlock': dormBlock,
      'department': department,
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  String get displayName => name;
}

// --- APPLIANCE MODEL ---
class Appliance {
  final String id;
  final String name;
  final String type;      
  final String location;  
  final double wattage;
  final double probDay;
  final double probNight;
  final double maxDurationHr;
  final String status;
  final List<double> states;    
  final int maxStateIndex;     

  Appliance({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.wattage,
    required this.probDay,
    required this.probNight,
    required this.maxDurationHr,
    required this.status,
    required this.states,
    required this.maxStateIndex,
  });

  Map<String, dynamic> toMap() {
    // High-level: Maps object to Firestore document format for ML backend compatibility.
    return {
      'name': name,
      'type': type,
      'location': location,
      'wattage': wattage,
      'prob_day': probDay,
      'prob_night': probNight,
      'max_duration_hr': maxDurationHr,
      'status': status,
      // Developer Expectation: 'states' and 'max_state_index' are mandatory for the Python FHMM engine.
      'states': states,
      'max_state_index': maxStateIndex,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory Appliance.fromFirestore(String id, Map<String, dynamic> data) {
  // High-level: Reconstructs object from Firestore document data.
  
  // Developer Expectation: Cast the dynamic 'states' list to double to prevent type mismatch errors.
    final List<dynamic> rawStates = data['states'] ?? [0.0, (data['wattage'] as num?)?.toDouble() ?? 0.0];
    final List<double> parsedStates = rawStates.map((e) => (e as num).toDouble()).toList();

    return Appliance(
      id: id,
      name: data['name'] ?? '',
      type: data['type'] ?? 'Unknown',           // Added
      location: data['location'] ?? 'General',   // Added
      wattage: (data['wattage'] as num?)?.toDouble() ?? 0.0,
      probDay: (data['prob_day'] as num?)?.toDouble() ?? 0.1,
      probNight: (data['prob_night'] as num?)?.toDouble() ?? 0.1,
      maxDurationHr: (data['max_duration_hr'] as num?)?.toDouble() ?? 1.0,
      status: data['status'] ?? 'pending',
      states: parsedStates,                      // Added
      maxStateIndex: (data['max_state_index'] as num?)?.toInt() ?? (parsedStates.length - 1), // Added
    );
  }
}

// --- REPORTING MODELS ---
class EnergyReportData {
  final String id;
  final ReportSummary summary;
  final ReportKPIs kpis;
  final List<DailyUsagePoint> usageTrend;
  final Map<String, double> applianceBreakdown;
  final Map<String, double> benchmarkBreakdown;
  final List<String> anomalies;
  final Map<int, double> hourlyUsage;
  final Map<String, double> costBreakdown;

  EnergyReportData({
    required this.id,
    required this.summary,
    required this.kpis,
    required this.usageTrend,
    required this.applianceBreakdown,
    required this.benchmarkBreakdown,
    required this.anomalies,
    required this.hourlyUsage,
    required this.costBreakdown,
  });

  factory EnergyReportData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return EnergyReportData(
      id: doc.id,
      summary: ReportSummary.fromMap(data['summary'] ?? {}),
      kpis: ReportKPIs.fromMap(data['kpis'] ?? {}),
      usageTrend: (data['usageTrend'] as List<dynamic>? ?? [])
          .map((item) => DailyUsagePoint.fromMap(item))
          .toList(),
      applianceBreakdown: Map<String, double>.from(data['breakdown'] ?? {}),
      benchmarkBreakdown: Map<String, double>.from(data['benchmark_breakdown'] ?? {}),
      anomalies: List<String>.from(data['anomalies'] ?? []),
      hourlyUsage: (data['hourlyUsage'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(int.parse(key), (value as num).toDouble()),
      ),
      costBreakdown: Map<String, double>.from(data['costBreakdown'] ?? {}),
    );
  }
}

class ReportSummary {
  final double totalConsumption;
  final double comparisonPercent;
  final double totalCost;
  final String keyIssue;
  final List<String> recommendations;

  ReportSummary({
    required this.totalConsumption,
    required this.comparisonPercent,
    required this.totalCost,
    required this.keyIssue,
    required this.recommendations,
  });

  factory ReportSummary.fromMap(Map<String, dynamic> map) {
    return ReportSummary(
      totalConsumption: (map['totalConsumption'] ?? 0).toDouble(),
      comparisonPercent: (map['comparisonPercent'] ?? 0).toDouble(),
      totalCost: (map['totalCost'] ?? 0).toDouble(),
      keyIssue: map['keyIssue'] ?? '',
      recommendations: List<String>.from(map['recommendations'] ?? []),
    );
  }
}

class ReportKPIs {
  final double totalKwh;
  final double dailyAvgKwh;
  final double peakKwh;
  final String peakTime;
  final double totalCost;
  final double changePercent;

  ReportKPIs({
    required this.totalKwh,
    required this.dailyAvgKwh,
    required this.peakKwh,
    required this.peakTime,
    required this.totalCost,
    required this.changePercent,
  });

  factory ReportKPIs.fromMap(Map<String, dynamic> map) {
    return ReportKPIs(
      totalKwh: (map['totalKwh'] ?? 0).toDouble(),
      dailyAvgKwh: (map['dailyAvgKwh'] ?? 0).toDouble(),
      peakKwh: (map['peakKwh'] ?? 0).toDouble(),
      peakTime: map['peakTime'] ?? '',
      totalCost: (map['totalCost'] ?? 0).toDouble(),
      changePercent: (map['changePercent'] ?? 0).toDouble(),
    );
  }
}

class DailyUsagePoint {
  final int day;
  final double value;
  
  DailyUsagePoint(this.day, this.value);

  factory DailyUsagePoint.fromMap(Map<String, dynamic> map) {
    return DailyUsagePoint(
      map['day'] ?? 0,
      (map['value'] ?? 0).toDouble(),
    );
  }
}