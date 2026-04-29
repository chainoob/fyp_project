import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:smartmeter/models/app_model.dart';
import 'package:cloud_functions/cloud_functions.dart';

abstract class EnergyRepository {
  Stream<Users?> get authStateChanges;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> saveUserProfile(String uid, Map<String, dynamic> userData);
  Future<String?> fetchUserRole(String uid);
  Future<bool> handleGoogleAuth(GoogleSignInAccount googleUser);
  Future signInWithGoogle();

  Stream<List<Appliance>> getAppliancesStream(String userId);
  Stream<List<Appliance>>  getPendingVerificationStream();

  Future<void> addAppliance(String userId, Appliance app);
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
        if (doc.exists) {
          return Users.fromFirestore(doc); 
        }
        return Users(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          name: firebaseUser.displayName ?? 'User',
          role: 'student',
        );
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> saveUserProfile(String uid, Map<String, dynamic> userData) async {
    await _db.collection('users').doc(uid).set(
      {
        ...userData,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(), 
      }, 
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  @override
  Future<String> fetchUserRole(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['role'] ?? 'student';
      }
    } catch (e) {
      rethrow;
    }
    return 'student';
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
      final String uid = userCred.user!.uid;
      final doc = await _db.collection('users').doc(uid).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<GoogleSignInAccount?> silentGoogleLogin() async {
    return await _googleSignIn.attemptLightweightAuthentication();
  }

  @override
  Stream<List<Appliance>> getAppliancesStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('appliances')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Appliance.fromFirestore(doc)).toList();
    });
  }

  @override
  Stream<List<Appliance>> getPendingVerificationStream() {
    return _db
        .collectionGroup('appliances')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Appliance.fromFirestore(doc)).toList();
    });
  }

  @override
  Future<String> getStudentDisplayId(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return "Unknown User";
      final data = doc.data() as Map<String, dynamic>;
      return data['studentId'] ?? data['displayName'] ?? uid;
    } catch (e) {
      return "Error Loading ID";
    }
  }

  @override
  Future<void> addAppliance(String userId, Appliance app) async {
    await _db.collection('users').doc(userId).collection('appliances').add(app.toMap());
  }

  @override
  Future<void> updateApplianceStatus(String userId, String appId, String status) async {
    await _db.collection('users').doc(userId).collection('appliances').doc(appId).update({
      'status': status,
      'verificationDate': status == 'active' ? FieldValue.serverTimestamp() : null,
    });
  }
  
@override
  Future<void> triggerDisaggregation(String userId, String billId, double totalBill) async {
    try {
      // Execute Cloud Function Proxy
      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('triggerDisaggregation');
          
      await callable.call({
        'blockId': userId, // Mapped to userId for Unit-level scope
        'totalBill': totalBill,
        'month': DateTime.now().toIso8601String().substring(0, 7),
        'trainModel': true,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Pipeline failure: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Network failure: $e');
    }
  }

  @override
  Stream<Map<String, dynamic>> getStudentGoalStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) => doc.exists ? doc.data()! : {});
  }

  @override
  Future<void> updateStudentGoal(String uid, double newGoal) async {
    await _db.collection('users').doc(uid).update({'energyGoal': newGoal});
  }

  @override
  Stream<Map<String, dynamic>> getCampusGoalStream() {
    return _db.collection('campus').doc('config').snapshots().map((doc) {
      if (!doc.exists) {
        doc.reference.set({'monthlyGoal': 5000, 'totalUsage': 0});
        return {'monthlyGoal': 5000, 'totalUsage': 0};
      }
      return doc.data()!;
    });
  }

  @override
  Future<void> updateCampusGoal(double newGoal) async {
    await _db.collection('campus').doc('config').set(
      {'monthlyGoal': newGoal}, 
      SetOptions(merge: true),
    );
  }
  
  @override
  Future<List<Map<String, dynamic>>> fetchBlocks() async {
    try {
      final snapshot = await _db.collection('blocks').orderBy('name').get();
      return snapshot.docs.map((d) => {'id': d.id, 'name': d['name'] ?? 'Unknown Block'}).toList();
    } catch (e) {
      throw Exception("Failed to fetch blocks: $e");
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUnits(String blockId) async {
    try {
      final snapshot = await _db.collection('blocks').doc(blockId).collection('units').orderBy('name').get();
      return snapshot.docs.map((d) => {'id': d.id, 'name': d['name'] ?? 'Unknown Unit'}).toList();
    } catch (e) {
      throw Exception("Failed to fetch units: $e");
    }
  }

  @override
@override
  Future<EnergyReportData> fetchEnergyReport({
    required String scope,
    required int month,
    required int year,
    String? blockId,
    String? unitId,
  }) async {
    // TODO: [Future Recommendation] Implement Staff 'Campus' Aggregation logic.
    // Currently bypasses complex cross-collection metric summation to prioritize Unit-level performance.
    if (scope == 'Campus') {
      throw UnimplementedError("Campus-wide aggregation deferred to v2.0");
    }

    try {
      Query query = _db.collection('disaggregation_results')
          .where('month', isEqualTo: month)
          .where('year', isEqualTo: year);

      String reportId = 'campus_aggregate';
      if (scope == 'Block' && blockId != null) {
        query = query.where('dormBlock', isEqualTo: blockId);
        reportId = 'block_$blockId';
      } else if (scope == 'Unit' && unitId != null) {
        query = query.where('userId', isEqualTo: unitId);
        reportId = 'unit_$unitId';
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        throw Exception("No AI analysis data available for this scope and timeframe.");
      }

      Map<String, double> aggregatedBreakdown = {};
      double totalEstimatedLoad = 0.0;
      double variance = 0.0;

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        totalEstimatedLoad += (data['estimated_load'] as num?)?.toDouble() ?? 0.0;
        variance += (data['difference'] as num?)?.toDouble() ?? 0.0;

        final bdRaw = data['breakdown'] as Map<String, dynamic>? ?? {};
        bdRaw.forEach((key, value) {
          aggregatedBreakdown[key] = (aggregatedBreakdown[key] ?? 0.0) + (value as num).toDouble();
        });
      }

      final totalCost = totalEstimatedLoad * 0.218;

      return EnergyReportData(
        id: reportId,
        summary: ReportSummary(
          totalConsumption: totalEstimatedLoad,
          // TODO: [Future Recommendation] Calculate historical baseline comparison
          comparisonPercent: 0.0, 
          totalCost: totalCost,
          keyIssue: variance > (totalEstimatedLoad * 0.1) 
              ? "High deviation detected between actual load and mapped appliances." 
              : "Appliance utilization aligns with total load.",
          recommendations: ["Ensure registered appliance lists are accurate in the database."],
        ),
        kpis: ReportKPIs(
          totalKwh: totalEstimatedLoad,
          dailyAvgKwh: totalEstimatedLoad / 30, 
          peakKwh: 0.0, 
          peakTime: "N/A", 
          totalCost: totalCost,
          changePercent: 0.0,
        ),
        // TODO: [Future Recommendation] Wire LSTM output arrays to usageTrend and hourlyUsage variables
        usageTrend: [], 
        applianceBreakdown: aggregatedBreakdown,
        hourlyUsage: {}, 
        costBreakdown: aggregatedBreakdown.map((k, v) => MapEntry(k, v * 0.218)),
      );

    } catch (e) {
      throw Exception("Backend Fetch Failed: $e");
    }
  }
}