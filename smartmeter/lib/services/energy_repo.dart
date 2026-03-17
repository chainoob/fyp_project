import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:smartmeter/models/app_model.dart';

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
  studentId: '',
  photoUrl: ''
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

  // --- 3. Role Management ---
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

  // --- 4. Google Sign-In Implementation ---

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
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id; 
    
          return Appliance.fromFirestore(doc);
        }).toList();
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
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          
          if (doc.reference.parent.parent != null) {
            data['userId'] = doc.reference.parent.parent!.id;
          }
          
          return Appliance.fromFirestore(doc); 
        }).toList();
      });
}

@override
  Future<String> getStudentDisplayId(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      
      if (!doc.exists || doc.data() == null) {
        return "Unknown User";
      }

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
    final url = Uri.parse('');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'userId': userId,
        'billTotal': totalBill,
        'month': DateTime.now().toIso8601String().substring(0, 7),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Disaggregation API Failed: ${response.body}');
    }
  }
  @override
  Stream<Map<String, dynamic>> getStudentGoalStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      // Return a map or a custom model if you have one
      return doc.exists ? doc.data()! : {}; 
    });
  }

  @override
  Future<void> updateStudentGoal(String uid, double newGoal) async {
    await _db.collection('users').doc(uid).update({'energyGoal': newGoal});
  }

  // --- CAMPUS/STAFF METHODS ---

  // Stream for shared campus goal
  @override
  Stream<Map<String, dynamic>> getCampusGoalStream() {
    return _db.collection('campus').doc('config').snapshots().map((doc) {
      if (!doc.exists) {
        // Create default if missing
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
      return snapshot.docs.map((d) => {
        'id': d.id,
        'name': d['name'] ?? 'Unknown Block'
      }).toList();
    } catch (e) {
      throw Exception("Failed to fetch blocks: $e");
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUnits(String blockId) async {
    try {
      final snapshot = await _db
          .collection('blocks')
          .doc(blockId)
          .collection('units')
          .orderBy('name')
          .get();
      return snapshot.docs.map((d) => {
        'id': d.id,
        'name': d['name'] ?? 'Unknown Unit'
      }).toList();
    } catch (e) {
      throw Exception("Failed to fetch units: $e");
    }
  }

  @override
  Future<EnergyReportData> fetchEnergyReport({
    required String scope,
    required int month,
    required int year,
    String? blockId,
    String? unitId,
  }) async {
    // =========================================================================
    // TODO: IMPLEMENT REAL BACKEND CONNECTION (Future Update)
    // =========================================================================
    // According to System Docs Section 5.3, the AI Engine writes results to 
    // the 'disaggregation_results' collection. You need to query that here.
    
    /*
    try {
      // 1. Construct Query
      Query query = _db.collection('disaggregation_results')
          .where('month', isEqualTo: month)
          .where('year', isEqualTo: year);

      // 2. Filter by Scope
      if (scope == 'Block' && blockId != null) {
        query = query.where('dormBlock', isEqualTo: blockId); 
      } else if (scope == 'Unit' && unitId != null) {
        query = query.where('userId', isEqualTo: unitId);
      }

      // 3. Fetch & Aggregate
      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
         // TODO: Loop through docs and sum up 'applianceBreakdown' map values
         // TODO: Calculate total cost based on the real aggregated kWh
         // return EnergyReportData(...); 
      }
    } catch (e) {
      debugPrint("Error fetching real reports: $e");
    }
    */

    // =========================================================================
    // MOCK DATA (Active Placeholder)
    // =========================================================================
    // Keeps the UI working until the Python AI engine is connected.
    
    await Future.delayed(const Duration(seconds: 2));
    final Random rng = Random();

    // Mocking 'applianceBreakdown' from Doc Section 5.3
    final breakdown = {
      'Fan': 350.0 + rng.nextInt(100),
      'Laptop': 150.0 + rng.nextInt(50),
      'Charger': 50.0 + rng.nextInt(20),
      'Lamp': 40.0 + rng.nextInt(20),
      'Iron': 120.0 + rng.nextInt(80),   
      'Kettle': 200.0 + rng.nextInt(100), 
      'Printer': 10.0 + rng.nextInt(10),
    };

    double totalKwh = breakdown.values.reduce((a, b) => a + b);
    
    // Scale down if viewing a specific unit to make it realistic
    if (scope == 'Unit') totalKwh /= 10; 

    double totalCost = totalKwh * 0.218; // RM 0.218 tariff
    
    return EnergyReportData(
      summary: ReportSummary(
        totalConsumption: totalKwh,
        comparisonPercent: 5.4, 
        totalCost: totalCost,
        keyIssue: "High usage detected in high-wattage appliances (Kettle/Iron).", 
        recommendations: [
          "Verify no prohibited appliances are in use.",
          "Check iron/kettle usage policy enforcement.",
        ],
      ),
      kpis: ReportKPIs(
        totalKwh: totalKwh,
        dailyAvgKwh: totalKwh / 30,
        peakKwh: totalKwh / 30 * 2.5,
        peakTime: "18:00 - 20:00", 
        totalCost: totalCost,
        changePercent: 5.4,
      ),
      usageTrend: List.generate(30, (i) => DailyUsagePoint(i + 1, (totalKwh/30) + rng.nextInt(10) - 5)),
      applianceBreakdown: breakdown,
      hourlyUsage: {for (var i = 0; i < 24; i++) i: (rng.nextDouble() * 5)},
      costBreakdown: breakdown.map((k, v) => MapEntry(k, v * 0.218)),
    );
  }
}