import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:smartmeter/models/app_model.dart';

abstract class EnergyRepository {
  Stream<Users?> get authStateChanges;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> register(String email, String password, Map<String, dynamic> userData);
  Future<String?> fetchUserRole(String uid);
  Future<bool> handleGoogleAuth(GoogleSignInAccount googleUser);
  Future signInWithGoogle();

    Stream<List<Appliance>> getAppliancesStream(String userId);
    Stream<List<Appliance>> getPendingVerificationStream();

    Future<void> addAppliance(String userId, Appliance app);
    Future<void> updateApplianceStatus(String userId, String appId, String status);
    Future<void> triggerDisaggregation(String userId, String billId, double totalBill);
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
  Future<void> register(String email, String password, Map<String, dynamic> additionalData) async {
  // Create Auth User
  final credential = await _auth.createUserWithEmailAndPassword(
  email: email,
  password: password
  );

  // Create Firestore Document
  if (credential.user != null) {
  await _db.collection('users').doc(credential.user!.uid).set({
  'uid': credential.user!.uid,
  'email': email,
  ...additionalData, 
  'createdAt': FieldValue.serverTimestamp(),
  });
  }
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
        .map((snapshot) => snapshot.docs.map((doc) => Appliance.fromFirestore(doc)).toList());
  }

  @override
  Stream<List<Appliance>> getPendingVerificationStream() {
    return _db
        .collectionGroup('appliances')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Appliance.fromFirestore(doc)).toList());
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
}