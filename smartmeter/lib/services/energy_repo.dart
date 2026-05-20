// smartmeter/lib/services/energy_repo.dart

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:smartmeter/models/app_model.dart';
import 'package:smartmeter/utils/logger.dart';

abstract class EnergyRepository {
  Stream<Users?> get authStateChanges;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> saveUserProfile(String uid, Map<String, dynamic> userData);
  Future<String?> fetchUserRole(String uid);
  Future<bool> handleGoogleAuth(GoogleSignInAccount? googleUser);
  Future<GoogleSignInAccount?> signInWithGoogle();

  Stream<List<Appliance>> getAppliancesStream(String userId);
  Stream<List<MapEntry<String, Appliance>>> getPendingVerificationStream();
  Future<void> saveAppliance(String userId, Appliance app);
  Future<void> deleteAppliance(String userId, String appId);
  Future<void> updateApplianceStatus(String userId, String appId, String status);
  Stream<DocumentSnapshot> listenToDisaggregation(String userId);
  Future<void> triggerDisaggregation(String userId, Map<String, dynamic> context);
  Future<String> getStudentDisplayId(String uid);

  Stream<List<double>> getLiveReadingsStream(String userId);

  Stream<Map<String, dynamic>> getStudentGoalStream(String uid);
  Future<void> updateStudentGoal(String uid, double newGoal);
  Future<void> saveFcmToken(String uid, String token);
  Stream<Map<String, dynamic>> getCampusGoalStream();
  Future<void> updateCampusGoal(double newGoal);

  Future<List<Map<String, dynamic>>> fetchBlocks();
  Future<List<Map<String, dynamic>>> fetchUnits(String blockId);

  Future<EnergyReportData> fetchEnergyReport({
    required String scope,
    required int month,
    required int year,
    String? blockId,
    String? unitId,
  });

  Future<void> sendFeedback({
    required String userId,
    required String applianceName,
    required bool actualState,
    required bool predictedState,
  });
}

class FirestoreRepository implements EnergyRepository {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  
  // High-Level: Re-mapped the endpoint target route variables to match the production container paths
  final String _baseUrl = 'https://ml-backend-338592292074.asia-southeast1.run.app';

  @override
  Stream<Users?> get authStateChanges {
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;

      try {
        final doc = await _db.collection('users').doc(firebaseUser.uid).get();
        if (doc.exists) return Users.fromFirestore(doc);

        return Users(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          name: firebaseUser.displayName ?? 'User',
          role: 'student',
        );
      } catch (e, stack) {
        AppLog.error('Auth State Mapping', e, stack);
        return null;
      }
    });
  }

  @override
  Future<void> signIn(String email, String password) async =>
      await _auth.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> saveUserProfile(String uid, Map<String, dynamic> userData) async {
    await _db.collection('users').doc(uid).set({
      ...userData,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  @override
  Future<String?> fetchUserRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['role'] as String?;
  }

  @override
  Future<GoogleSignInAccount?> signInWithGoogle() async {
    return await _googleSignIn.authenticate();
  }

  @override
  Future<bool> handleGoogleAuth(GoogleSignInAccount? googleUser) async {
    if (googleUser == null) return false;
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: null,
      idToken: googleAuth.idToken,
    );

    try {
      final UserCredential userCred = await _auth.signInWithCredential(credential);
      final doc = await _db.collection('users').doc(userCred.user!.uid).get();
      return doc.exists;
    } catch (e) { return false; }
  }

  @override
  Stream<List<Appliance>> getAppliancesStream(String userId) {
    return _db.collection('users').doc(userId).collection('appliances').snapshots().map(
      (snap) => snap.docs.map((doc) => Appliance.fromFirestore(doc.id, doc.data())).toList()
    );
  }

  @override
  Stream<List<MapEntry<String, Appliance>>> getPendingVerificationStream() {
    return _db.collectionGroup('appliances')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
          final userId = doc.reference.parent.parent!.id;
          final appliance = Appliance.fromFirestore(doc.id, doc.data());
          return MapEntry(userId, appliance);
        }).toList());
  }

  @override
  Future<void> saveAppliance(String userId, Appliance appliance) async {
    final collection = _db.collection('users').doc(userId).collection('appliances');
    if (appliance.id.isEmpty) {
      await collection.add(appliance.toMap());
    } else {
      await collection.doc(appliance.id).set(appliance.toMap());
    }
  }

  @override
  Future<void> deleteAppliance(String userId, String appId) async =>
      await _db.collection('users').doc(userId).collection('appliances').doc(appId).delete();

  @override
  Future<void> updateApplianceStatus(String userId, String appId, String status) async =>
      await _db.collection('users').doc(userId).collection('appliances').doc(appId).update({'status': status});

 @override
 Future<void> triggerDisaggregation(String userId, Map<String, dynamic> context) async {
    final url = Uri.parse('$_baseUrl/api/v1/trigger-disaggregation');    
    final User? user = _auth.currentUser;
    if (user == null) throw Exception("User authorization missing.");
    final String? idToken = await user.getIdToken();
    
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'userId': userId,
        'totalBill': context['totalBill'],
        'month': context['month'],
        'year': context['year'],
        'scope': context['scope'] ?? 'Unit',
        'trainModel': context['trainModel'] ?? false,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 202) {
      final Map<String, dynamic> decoded = jsonDecode(response.body);
      
      if (decoded['status'] == 'success' && decoded['data'] != null) {
        final Map<String, dynamic> dataPayload = decoded['data'] as Map<String, dynamic>;
        
        // High-Level: Synchronize incoming HTTP response directly to Firestore.
        // Developer Expectation: This implicitly regenerates the deleted collection.
        await _db.collection('disaggregation_results').add({
          'userId': dataPayload['userId'] ?? userId,
          'month': dataPayload['month'] ?? context['month'],
          'year': dataPayload['year'] ?? context['year'],
          'carbonFootprint': (dataPayload['carbon_footprint'] as num?)?.toDouble() ?? 0.0,
          'summary': {
            'totalConsumption': (dataPayload['estimated_load'] as num?)?.toDouble() ?? 0.0,
            'totalCost': (dataPayload['estimated_cost'] as num?)?.toDouble() ?? (context['totalBill'] as num).toDouble(),
            'keyIssue': (dataPayload['recommendations'] as List?)?.isNotEmpty == true 
                ? (dataPayload['recommendations'] as List).first.toString() 
                : "Optimal efficiency.",
            'recommendations': List<String>.from(dataPayload['recommendations'] ?? []),
          },
          'kpis': {
            'totalKwh': (dataPayload['estimated_load'] as num?)?.toDouble() ?? 0.0,
            'dailyAvgKwh': ((dataPayload['estimated_load'] as num?)?.toDouble() ?? 0.0) / 30,
            'peakKwh': 0.0, 
            'peakTime': "00:00",
            'totalCost': (dataPayload['estimated_cost'] as num?)?.toDouble() ?? (context['totalBill'] as num).toDouble(),
          },
          'applianceBreakdown': Map<String, double>.from(dataPayload['breakdown'] ?? {}),
          'benchmarkBreakdown': Map<String, double>.from(dataPayload['benchmark_breakdown'] ?? {}),
          'anomalies': List<String>.from(dataPayload['anomalies'] ?? []),
          'hourlyUsage': Map<String, dynamic>.from(dataPayload['hourlyUsage'] ?? {}),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        throw Exception(decoded['message'] ?? "Pipeline logic failure.");
      }
    } else {
      try {
        final Map<String, dynamic> errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? errorData['detail'] ?? "Server Rejection: ${response.statusCode}");
      } catch (_) {
        throw Exception("Cloud Run ingestion rejected payload status code: ${response.statusCode}");
      }
    }
  }

  @override
  Future<String> getStudentDisplayId(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    return data['studentId'] ?? data['displayName'] ?? uid;
  }

  @override
  Stream<List<double>> getLiveReadingsStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('telemetry')
        .orderBy('timestamp', descending: true)
        .limit(10) 
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => (doc.data()['wattage'] as num).toDouble())
            .toList());
  }

  @override
  Stream<Map<String, dynamic>> getStudentGoalStream(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((doc) => doc.data() ?? {});

  @override
  Future<void> updateStudentGoal(String uid, double newGoal) async =>
      await _db.collection('users').doc(uid).update({'energyGoal': newGoal});

  @override
  Future<void> saveFcmToken(String uid, String token) async =>
      await _db.collection('users').doc(uid).update({'fcmToken': token});

  @override
  Stream<Map<String, dynamic>> getCampusGoalStream() =>
      _db.collection('campus').doc('config').snapshots().map((doc) => doc.data() ?? {});

  @override
  Future<void> updateCampusGoal(double newGoal) async =>
      await _db.collection('campus').doc('config').set({'monthlyGoal': newGoal}, SetOptions(merge: true));

  @override
  Future<List<Map<String, dynamic>>> fetchBlocks() async {
    final snap = await _db.collection('blocks').orderBy('name').get();
    return snap.docs.map((d) => {'id': d.id, 'name': d['name'] ?? 'Unknown'}).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUnits(String blockId) async {
    final snap = await _db.collection('blocks').doc(blockId).collection('units').orderBy('name').get();
    return snap.docs.map((d) => {'id': d.id, 'name': d['name'] ?? 'Unknown'}).toList();
  }

  @override
  Future<EnergyReportData> fetchEnergyReport({
    String? blockId,
    required int month,
    required String scope,
    String? unitId,
    required int year,
  }) async {
    try {
      final lookupKey = unitId ?? blockId ?? 'aggregate';

      final currentSnapshot = await _db.collection('disaggregation_results')
          .where('userId', isEqualTo: lookupKey)
          .where('month', isEqualTo: month)
          .where('year', isEqualTo: year)
          .limit(1)
          .get();

      if (currentSnapshot.docs.isEmpty) {
        throw Exception("Analysis data unavailable for $lookupKey ($month/$year). Awaiting staff bill submission.");
      }
      final data = currentSnapshot.docs.first.data();

      int prevMonth = month == 1 ? 12 : month - 1;
      int prevYear = month == 1 ? year - 1 : year;
      
      final prevSnapshot = await _db.collection('disaggregation_results')
          .where('userId', isEqualTo: lookupKey)
          .where('month', isEqualTo: prevMonth)
          .where('year', isEqualTo: prevYear)
          .limit(1)
          .get();

      final Map<String, dynamic> summaryMap = data['summary'] as Map<String, dynamic>? ?? {};
      final Map<String, dynamic> kpisMap = data['kpis'] as Map<String, dynamic>? ?? {};

      double currentLoad = (summaryMap['totalConsumption'] as num?)?.toDouble() ?? 
                           (kpisMap['totalKwh'] as num?)?.toDouble() ?? 
                           (data['estimated_load'] as num?)?.toDouble() ?? 0.0;

      double estimatedCost = (summaryMap['totalCost'] as num?)?.toDouble() ?? 
                             (kpisMap['totalCost'] as num?)?.toDouble() ?? 
                             (data['estimated_cost'] as num?)?.toDouble() ?? 0.0;
      
      double carbonFootprint = (data['carbonFootprint'] as num?)?.toDouble() ?? 
                               (data['carbon_footprint'] as num?)?.toDouble() ?? 0.0;
      
      double comparisonPercent = 0.0;
      if (prevSnapshot.docs.isNotEmpty) {
        final prevData = prevSnapshot.docs.first.data();
        final Map<String, dynamic> prevSummary = prevData['summary'] as Map<String, dynamic>? ?? {};
        double prevLoad = (prevSummary['totalConsumption'] as num?)?.toDouble() ?? 0.0;
        if (prevLoad > 0) {
          comparisonPercent = ((currentLoad - prevLoad) / prevLoad) * 100;
        }
      }

      final breakdown = Map<String, double>.from(data['applianceBreakdown'] ?? data['breakdown'] ?? {});
      
      final hourly = (data['hourlyUsage'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(int.parse(k), (v as num).toDouble())
      );

      double peakKwh = (kpisMap['peakKwh'] as num?)?.toDouble() ?? 0.0;
      String peakTime = kpisMap['peakTime'] as String? ?? "00:00";
      
      if (peakKwh == 0.0 && hourly.isNotEmpty) {
        int peakHour = 0;
        hourly.forEach((hour, val) {
          if (val > peakKwh) {
            peakKwh = val;
            peakHour = hour;
          }
        });
        peakTime = "${peakHour.toString().padLeft(2, '0')}:00";
      }

      final recommendations = List<String>.from(summaryMap['recommendations'] ?? data['recommendations'] ?? []);

      return EnergyReportData(
        id: lookupKey,
        summary: ReportSummary(
          totalConsumption: currentLoad,
          comparisonPercent: comparisonPercent,
          totalCost: estimatedCost,
          keyIssue: summaryMap['keyIssue'] ?? (recommendations.isNotEmpty ? recommendations.first : "Optimal efficiency."),
          recommendations: recommendations,
        ),
        kpis: ReportKPIs(
          totalKwh: currentLoad,
          dailyAvgKwh: currentLoad / 30,
          peakKwh: peakKwh,
          peakTime: peakTime,
          totalCost: estimatedCost,
          changePercent: comparisonPercent,
        ),
        carbonFootprint: carbonFootprint,
        usageTrend: [], 
        applianceBreakdown: breakdown,
        benchmarkBreakdown: Map<String, double>.from(data['benchmarkBreakdown'] ?? data['benchmark_breakdown'] ?? {}),
        anomalies: List<String>.from(data['anomalies'] ?? []),
        hourlyUsage: hourly,
        costBreakdown: breakdown.map((key, value) => MapEntry(key, currentLoad > 0 ? value * (estimatedCost / currentLoad) : 0.0)),
      );
    } catch (e) {
      rethrow;
    }
  }
  
  @override
  Stream<DocumentSnapshot<Object?>> listenToDisaggregation(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('daily_usage')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.first);
  }
  
  @override
  Future<void> sendFeedback({
    required String userId,
    required String applianceName,
    required bool actualState,
    required bool predictedState,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) throw Exception("User session missing.");

    final String? idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/v1/feedback'),
      body: jsonEncode({
        'user_id': userId,
        'appliance_name': applianceName,
        'actual_state': actualState,
        'predicted_state': predictedState,
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
    );

    if (response.statusCode != 200) {
      AppLog.error('Feedback Submission', response.body);
      throw Exception("Failed to sync feedback with AI engine.");
    }
  }
}