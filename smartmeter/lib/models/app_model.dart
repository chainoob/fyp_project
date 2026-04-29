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
  final String ownerId;
  final String name;
  final String type;
  final int wattage;
  final String status;
  final String? room;
  final DateTime? verificationDate;

  const Appliance({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    required this.wattage,
    this.status = 'pending',
    this.room,
    this.verificationDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'name': name,
      'type': type,
      'wattage': wattage,
      'status': status,
      'room': room,
      'verificationDate': verificationDate != null ? Timestamp.fromDate(verificationDate!) : null,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory Appliance.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    String resolvedOwnerId = data['ownerId'] ?? '';
    if (resolvedOwnerId.isEmpty && doc.reference.parent.parent != null) {
      resolvedOwnerId = doc.reference.parent.parent!.id;
    }

    return Appliance(
      id: doc.id,
      ownerId: resolvedOwnerId,
      name: data['name'] ?? 'Unknown Device',
      type: data['type'] ?? 'other',
      wattage: data['wattage'] ?? 0,
      status: data['status'] ?? 'pending',
      room: data['room'],
      verificationDate: (data['verificationDate'] as Timestamp?)?.toDate(),
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
  final Map<int, double> hourlyUsage;
  final Map<String, double> costBreakdown;

  EnergyReportData({
    required this.id,
    required this.summary,
    required this.kpis,
    required this.usageTrend,
    required this.applianceBreakdown,
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
      applianceBreakdown: Map<String, double>.from(data['applianceBreakdown'] ?? {}),
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