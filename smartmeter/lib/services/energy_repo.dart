import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:smartmeter/models/app_model.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:smartmeter/utils/logger.dart';

abstract class EnergyRepository {
  Stream<Users?> get authStateChanges;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> saveUserProfile(String uid, Map<String, dynamic> userData);
  Future<String?> fetchUserRole(String uid);
  Future<bool> handleGoogleAuth(GoogleSignInAccount? googleUser);
  Future<GoogleSignInAccount?> signInWithGoogle();

  // Unified Appliance Management
  Stream<List<Appliance>> getAppliancesStream(String userId);
  Stream<List<MapEntry<String, Appliance>>> getPendingVerificationStream();
  Future<void> saveAppliance(String userId, Appliance app);
  Future<void> deleteAppliance(String userId, String appId);
  Future<void> updateApplianceStatus(String userId, String appId, String status);

  Future<String> getStudentDisplayId(String uid);
  Future<void> triggerDisaggregation(String userId, String billId, double totalBill);

  Stream<Map<String, dynamic>> getStudentGoalStream(String uid);
  Future<void> updateStudentGoal(String uid, double newGoal);
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
}

// smartmeter/lib/services/energy_repo.dart

class FirestoreRepository implements EnergyRepository {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

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
    // Merges user profile data with server-side timestamps.
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
    // Authenticates with Firebase using Google provider credentials.
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
    // Maps collectionGroup documents to owner-appliance pairs for the provider.
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
  Future<void> triggerDisaggregation(String userId, String billId, double totalBill) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1').httpsCallable('triggerDisaggregation');
    await callable.call({
      'blockId': userId,
      'totalBill': totalBill,
      'month': DateTime.now().toIso8601String().substring(0, 7),
      'trainModel': true,
    });
  }

  @override
  Future<String> getStudentDisplayId(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    return data['studentId'] ?? data['displayName'] ?? uid;
  }

  @override
  Stream<Map<String, dynamic>> getStudentGoalStream(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((doc) => doc.data() ?? {});

  @override
  Future<void> updateStudentGoal(String uid, double newGoal) async =>
      await _db.collection('users').doc(uid).update({'energyGoal': newGoal});

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
  
  double _getElectricityRate() => 0.218; // Placeholder for future remote configuration.

  @override
  Future<EnergyReportData> fetchEnergyReport({
    String? blockId,
    required int month,
    required String scope,
    String? unitId,
    required int year,
  }) async {
    // Retrieves analysis metrics and calculates historical performance trends.
    try {
      final currentSnapshot = await _db.collection('disaggregation_results')
          .where('userId', isEqualTo: unitId)
          .where('month', isEqualTo: month)
          .where('year', isEqualTo: year)
          .limit(1)
          .get();

      if (currentSnapshot.docs.isEmpty) throw Exception("Analysis data unavailable.");
      final data = currentSnapshot.docs.first.data();

      int prevMonth = month == 1 ? 12 : month - 1;
      int prevYear = month == 1 ? year - 1 : year;
      
      final prevSnapshot = await _db.collection('disaggregation_results')
          .where('userId', isEqualTo: unitId)
          .where('month', isEqualTo: prevMonth)
          .where('year', isEqualTo: prevYear)
          .limit(1)
          .get();

      double currentLoad = (data['estimated_load'] as num).toDouble();
      double comparisonPercent = 0.0;
      if (prevSnapshot.docs.isNotEmpty) {
        double prevLoad = (prevSnapshot.docs.first.data()['estimated_load'] as num).toDouble();
        comparisonPercent = ((currentLoad - prevLoad) / prevLoad) * 100;
      }

      // Developer Expectation: Move rate to a remote config or database field in production.
      final double electricityRate = _getElectricityRate(); 
      final breakdown = Map<String, double>.from(data['breakdown'] ?? {});
      final hourly = (data['hourlyUsage'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(int.parse(k), (v as num).toDouble())
      );

      double peakKwh = 0.0;
      int peakHour = 0;
      hourly.forEach((hour, val) {
        if (val > peakKwh) {
          peakKwh = val;
          peakHour = hour;
        }
      });

      final recommendations = List<String>.from(data['recommendations'] ?? []);

      return EnergyReportData(
        id: unitId ?? 'aggregate',
        summary: ReportSummary(
          totalConsumption: currentLoad,
          comparisonPercent: comparisonPercent,
          totalCost: currentLoad * electricityRate,
          keyIssue: recommendations.isNotEmpty ? recommendations.first : "Optimal efficiency.",
          recommendations: recommendations,
        ),
        kpis: ReportKPIs(
          totalKwh: currentLoad,
          dailyAvgKwh: currentLoad / 30,
          peakKwh: peakKwh,
          peakTime: "${peakHour.toString().padLeft(2, '0')}:00",
          totalCost: currentLoad * electricityRate,
          changePercent: comparisonPercent,
        ),
        usageTrend: [], 
        applianceBreakdown: breakdown,
        hourlyUsage: hourly,
        costBreakdown: breakdown.map((key, value) => MapEntry(key, value * electricityRate)),
      );
    } catch (e) {
      rethrow;
    }
  }
}