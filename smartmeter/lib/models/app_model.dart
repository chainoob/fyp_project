import 'package:cloud_firestore/cloud_firestore.dart';

class Users {
  final String uid;
  final String name;
  final String email;
  final String role; 
  final String? studentId;
  final String? dormBlock;
  final String? assignedUnitId;
  final String? assignedRoomName;
  final String? photoUrl;

  const Users({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.studentId,
    this.dormBlock,
    this.assignedUnitId,
    this.assignedRoomName,
    this.photoUrl
  });

  factory Users.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(doc.data() as Map? ?? {});
    
    final Map<String, dynamic> profile = data['profile'] is Map ? Map<String, dynamic>.from(data['profile'] as Map) : const <String, dynamic>{};
    final Map<String, dynamic> location = data['location'] is Map ? Map<String, dynamic>.from(data['location'] as Map) : const <String, dynamic>{};

    final String name = profile['name']?.toString() ?? data['displayName']?.toString() ?? 'Unknown';
    final String role = profile['role']?.toString().toLowerCase() ?? data['role']?.toString() ?? 'student';
    final String? studentId = profile['studentId']?.toString() ?? data['studentId']?.toString();
    final String? dormBlock = location['block_id']?.toString() ?? data['dormBlock']?.toString();
    final String? assignedUnitId = location['unit_id']?.toString() ?? data['assignedUnitId']?.toString();
    final String? assignedRoomName = location['room_name']?.toString() ?? data['assignedRoomName']?.toString();

    return Users(
      uid: doc.id,
      name: name,
      email: data['email']?.toString() ?? '',
      role: role,
      studentId: studentId,
      dormBlock: dormBlock,
      assignedUnitId: assignedUnitId,
      assignedRoomName: assignedRoomName,
      photoUrl: data['photoUrl']?.toString()
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': name,
      'email': email,
      'role': role,
      'studentId': studentId,
      'dormBlock': dormBlock,
      'assignedUnitId': assignedUnitId,
      'assignedRoomName': assignedRoomName,
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  String get displayName => name;
}

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

  final String? imageBase64;
 
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
    this.imageBase64,
  });
 
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'location': location,
      'wattage': wattage,
      'prob_day': probDay,
      'prob_night': probNight,
      'max_duration_hr': maxDurationHr,
      'status': status,
      'states': states,
      'max_state_index': maxStateIndex,
      'imageBase64': imageBase64,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
 
  factory Appliance.fromFirestore(String id, Map<String, dynamic> data) {
    final List<dynamic> rawStates = data['states'] ?? [0.0, (data['wattage'] as num?)?.toDouble() ?? 0.0];
    final List<double> parsedStates = rawStates.map((e) => (e as num).toDouble()).toList();
 
    return Appliance(
      id: id,
      name: data['name'] ?? '',
      type: data['type'] ?? 'Unknown',           
      location: data['location'] ?? 'General',   
      wattage: (data['wattage'] as num?)?.toDouble() ?? 0.0,
      probDay: (data['prob_day'] as num?)?.toDouble() ?? 0.1,
      probNight: (data['prob_night'] as num?)?.toDouble() ?? 0.1,
      maxDurationHr: (data['max_duration_hr'] as num?)?.toDouble() ?? 1.0,
      status: data['status'] ?? 'pending',
      states: parsedStates,                      
      maxStateIndex: (data['max_state_index'] as num?)?.toInt() ?? (parsedStates.length - 1), 
      imageBase64: data['imageBase64'],
    );
  }
}

class EnergyReportData {
  final String id;
  final ReportSummary summary;
  final ReportKPIs kpis;
  final double carbonFootprint; 
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
    required this.carbonFootprint,
    required this.usageTrend,
    required this.applianceBreakdown,
    required this.benchmarkBreakdown,
    required this.anomalies,
    required this.hourlyUsage,
    required this.costBreakdown,
  });

  List<DailyUsagePoint> get usageTrendOrDefault {
    if (usageTrend.isNotEmpty) return usageTrend;
    return List.generate(30, (i) => DailyUsagePoint(i + 1, 0.0));
  }

  static double _safeDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  factory EnergyReportData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    final Map<String, dynamic> summaryMap = (data['summary'] is Map) ? data['summary'] : {};
    final Map<String, dynamic> kpisMap = (data['kpis'] is Map) ? data['kpis'] : {};

    double totalKwh = _safeDouble(summaryMap['totalConsumption']) != 0.0 
        ? _safeDouble(summaryMap['totalConsumption'])
        : _safeDouble(kpisMap['totalKwh']) != 0.0
            ? _safeDouble(kpisMap['totalKwh'])
            : _safeDouble(data['estimated_load']);

    double totalCost = _safeDouble(summaryMap['totalCost']) != 0.0
        ? _safeDouble(summaryMap['totalCost'])
        : _safeDouble(kpisMap['totalCost']) != 0.0
            ? _safeDouble(kpisMap['totalCost'])
            : _safeDouble(data['estimated_cost']);

    double carbonFootprint = _safeDouble(data['carbonFootprint']) != 0.0
        ? _safeDouble(data['carbonFootprint'])
        : _safeDouble(data['carbon_footprint']);

    Map<int, double> parsedHourly = {};
    
    if (data['hourly_vector'] is List) {
      final list = data['hourly_vector'] as List;
      for (int i = 0; i < list.length; i++) {
        parsedHourly[i] = _safeDouble(list[i]);
      }
    } else if (data['hourlyUsage'] is List) {
      final list = data['hourlyUsage'] as List;
      for (int i = 0; i < list.length; i++) {
        parsedHourly[i] = _safeDouble(list[i]);
      }
    } else if (data['hourlyUsage'] is Map) {
      final map = data['hourlyUsage'] as Map;
      map.forEach((key, value) {
        final parsedKey = double.tryParse(key.toString())?.toInt() ?? 0;
        parsedHourly[parsedKey] = _safeDouble(value);
      });
    }

    final recommendations = List<String>.from(data['recommendations'] ?? summaryMap['recommendations'] ?? []);
    final keyIssue = summaryMap['keyIssue']?.toString() ?? (recommendations.isNotEmpty ? recommendations.first : "Consumption nominal.");

    return EnergyReportData(
      id: doc.id,
      summary: ReportSummary(
        totalConsumption: totalKwh,
        comparisonPercent: _safeDouble(summaryMap['comparisonPercent']),
        totalCost: totalCost,
        keyIssue: keyIssue,
        recommendations: recommendations,
      ),
      kpis: ReportKPIs(
        totalKwh: totalKwh,
        dailyAvgKwh: _safeDouble(kpisMap['dailyAvgKwh']) != 0.0 ? _safeDouble(kpisMap['dailyAvgKwh']) : (totalKwh / 30),
        peakKwh: _safeDouble(kpisMap['peakKwh']),
        peakTime: kpisMap['peakTime']?.toString() ?? "00:00",
        totalCost: totalCost,
        changePercent: _safeDouble(kpisMap['changePercent']),
      ),
      usageTrend: (data['usageTrend'] as List<dynamic>? ?? []).map((item) => DailyUsagePoint.fromMap(item)).toList(),
      carbonFootprint: carbonFootprint,
      
      applianceBreakdown: Map<String, double>.from(
        (data['applianceBreakdown'] ?? data['breakdown'] ?? {}).map(
          (key, value) => MapEntry(key.toString(), _safeDouble(value)),
        ),
      ),
      benchmarkBreakdown: Map<String, double>.from(
        (data['benchmark_breakdown'] ?? data['benchmarkBreakdown'] ?? {}).map(
          (key, value) => MapEntry(key.toString(), _safeDouble(value)),
        ),
      ),
      anomalies: List<String>.from(data['anomalies'] ?? []),
      hourlyUsage: parsedHourly,
      costBreakdown: Map<String, double>.from(
        (data['costBreakdown'] is Map ? data['costBreakdown'] : {}).map(
          (key, value) => MapEntry(key.toString(), _safeDouble(value)),
        ),
      ),
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

  static double calculateMalaysianTariffA(double currentKwh) {
    double block1 = currentKwh > 200 ? 200 : currentKwh;
    double block2 = currentKwh > 200 ? (currentKwh > 300 ? 100 : currentKwh - 200) : 0;
    double block3 = currentKwh > 300 ? (currentKwh > 600 ? 300 : currentKwh - 300) : 0;

    double cost1 = block1 * 0.218;
    double cost2 = block2 * 0.334;
    double cost3 = block3 * 0.516;
    return cost1 + cost2 + cost3;
  }

  factory ReportSummary.fromMap(Map<String, dynamic> map) {
    return ReportSummary(
      totalConsumption: (map['totalConsumption'] as num?)?.toDouble() ?? 0.0,
      comparisonPercent: (map['comparisonPercent'] as num?)?.toDouble() ?? 0.0,
      totalCost: (map['totalCost'] as num?)?.toDouble() ?? 0.0,
      keyIssue: map['keyIssue']?.toString() ?? "Consumption nominal.",
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
  final Map<String, double> applianceBreakdown;
  final Map<String, double> manualOverrides;
  final Map<int, double> hourlyUsage;
  
  DailyUsagePoint(
    this.day, 
    this.value, {
    this.applianceBreakdown = const {},
    this.manualOverrides = const {},
    this.hourlyUsage = const {},
  });

  factory DailyUsagePoint.fromMap(Map<String, dynamic> map) {
    final Map<String, double> parsedAppliance = {};
    final Map<String, dynamic> rawAppliance = Map<String, dynamic>.from(map['applianceBreakdown'] ?? map['appliance_breakdown'] ?? {});
    rawAppliance.forEach((k, v) {
      parsedAppliance[k] = (v as num).toDouble();
    });

    final Map<String, double> parsedManual = {};
    final Map<String, dynamic> rawManual = Map<String, dynamic>.from(map['manualOverrides'] ?? map['manual_overrides'] ?? {});
    rawManual.forEach((k, v) {
      parsedManual[k] = (v as num).toDouble();
    });

    final Map<int, double> parsedHourly = {};
    final Map<String, dynamic> rawHourly = Map<String, dynamic>.from(map['hourlyUsage'] ?? map['hourly_usage'] ?? {});
    rawHourly.forEach((k, v) {
      final int hour = int.tryParse(k) ?? 0;
      parsedHourly[hour] = (v as num).toDouble();
    });

    return DailyUsagePoint(
      map['day'] ?? 0,
      (map['value'] ?? 0).toDouble(),
      applianceBreakdown: parsedAppliance,
      manualOverrides: parsedManual,
      hourlyUsage: parsedHourly,
    );
  }
}

class ForecastResponse {
  final String userId;
  final int targetMonth;
  final int targetYear;
  final double currentConsumption;
  final double projectedAddition;
  final double estimatedEndOfMonthTotal;
  final String methodApplied;
  final Map<int, double> mcmcHourlyProfile;

  ForecastResponse({
    required this.userId,
    required this.targetMonth,
    required this.targetYear,
    required this.currentConsumption,
    required this.projectedAddition,
    required this.estimatedEndOfMonthTotal,
    required this.methodApplied,
    required this.mcmcHourlyProfile,
  });

  factory ForecastResponse.fromJson(Map<String, dynamic> json) {
    Map<int, double> parsedHourly = {};
    if (json['mcmc_hourly_profile'] is Map) {
      final map = json['mcmc_hourly_profile'] as Map;
      map.forEach((key, value) {
        final parsedKey = int.tryParse(key.toString()) ?? 0;
        parsedHourly[parsedKey] = (value as num).toDouble();
      });
    }

    return ForecastResponse(
      userId: json['userId'] ?? '',
      targetMonth: json['targetMonth'] ?? 0,
      targetYear: json['targetYear'] ?? 0,
      currentConsumption: (json['currentConsumption'] ?? 0.0).toDouble(),
      projectedAddition: (json['projectedAddition'] ?? 0.0).toDouble(),
      estimatedEndOfMonthTotal: (json['estimatedEndOfMonthTotal'] ?? 0.0).toDouble(),
      methodApplied: json['methodApplied'] ?? 'unknown',
      mcmcHourlyProfile: parsedHourly,
    );
  }
}