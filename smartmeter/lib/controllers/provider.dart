import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:smartmeter/models/app_model.dart';
import 'package:smartmeter/services/energy_repo.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppAuthProvider extends ChangeNotifier {
  final EnergyRepository _repo;

  Users? _currentUser;
  GoogleSignInAccount? _pendingGoogleUser; 
  String? _role;
  bool _isLoading = false;

  AppAuthProvider(this._repo) {
    _repo.authStateChanges.listen((user) {
      _currentUser = user;
      if (user != null) {
        fetchUserRole();
      }
      notifyListeners();
    });
  }

  Users? get currentUser => _currentUser;
  GoogleSignInAccount? get pendingGoogleUser => _pendingGoogleUser;
  bool get loggedIn => _currentUser != null;
  bool get isStaff => _role == 'staff';
  bool get isLoading => _isLoading;

  // --- 1. LOGIN (Standard) ---
  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _repo.signIn(email, password);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- 2. SIGN UP ---
  Future<void> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> additionalData,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _repo.register(email, password, additionalData);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- 3. GOOGLE LOGIN (Interactive) ---

  Future<bool> googleLogin() async {
    try {
      final googleUser = await _repo.signInWithGoogle();

      if (googleUser != null) {
        final bool userExists = await finalizeGoogleSignIn(googleUser);
        return userExists;
      }
      return false;
    } catch (e) {
      rethrow;
    }
  }

  // --- 4. FINALIZE GOOGLE (Logic) ---
  Future<bool> finalizeGoogleSignIn(GoogleSignInAccount googleUser) async {
    try {
      final bool userExists = await _repo.handleGoogleAuth(googleUser);
      if (userExists) {
        await fetchUserRole();
        _pendingGoogleUser = null;
        notifyListeners();
      }
      else{
        _pendingGoogleUser = googleUser;
      }
      return userExists;
    } catch (e) {
      rethrow;
    }
  }

  // --- 5. LOGOUT (Consolidated) ---
  Future<void> signOut() async {
    await _repo.signOut();
    _role = null;
    notifyListeners();
  }

  // --- 6. FETCH ROLE ---
  Future<void> fetchUserRole() async {
    if (_currentUser == null) return;
    try {
      _role = await _repo.fetchUserRole(_currentUser!.uid);
    } catch (e) {
      _role = 'student';
    }
    notifyListeners();
  }
}

class ApplianceProvider extends ChangeNotifier {
  final EnergyRepository _repo;
  List<Appliance> _appliances = [];
  StreamSubscription? _streamSub;

  ApplianceProvider(this._repo);

  List<Appliance> get appliances => _appliances;

  void subscribeToUser(String userId) {
    _streamSub?.cancel();
    _streamSub = _repo.getAppliancesStream(userId).listen((data) {
      _appliances = data;
      notifyListeners();
    });
  }

  void subscribeToQueue() {
    _streamSub?.cancel();
    _streamSub = _repo.getPendingVerificationStream().listen((data) {
      _appliances = data;
      notifyListeners();
    });
  }

  Future<void> add(String name, String type, int watts, String room) async {
  
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception("User not logged in");
  
  final String safeUid = user.uid;

  const status = 'pending';
  
  final newAppliance = Appliance(
    id: '', 
    ownerId: safeUid,
    name: name,
    type: type,
    wattage: watts,
    room: room,
    status: status,
    verificationDate: status == 'active' ? DateTime.now() : null,
  );

  await _repo.addAppliance(safeUid, newAppliance);
}

  Future<void> approve(String userId, String appId) async =>
      await _repo.updateApplianceStatus(userId, appId, 'active');

  Future<void> reject(String userId, String appId) async =>
      await _repo.updateApplianceStatus(userId, appId, 'rejected');

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}

class GoalProvider extends ChangeNotifier {
  double _targetKwh = 0.0;
  double _currentUsageKwh = 0.0;

  double get target => _targetKwh;
  double get current => _currentUsageKwh;

  double get progress {
    if (_targetKwh <= 0) return 0.0;
    return (_currentUsageKwh / _targetKwh).clamp(0.0, 1.0);
  }

  bool get isOverBudget => _targetKwh > 0 && _currentUsageKwh > _targetKwh;

  GoalProvider() {
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    _targetKwh = prefs.getDouble('energy_goal') ?? 0.0;

    // Future integration: Fetch real-time usage from Firestore here.
    // _currentUsageKwh = await repository.getCurrentMonthUsage();

    notifyListeners();
  }

  Future<void> setGoal(double newGoal) async {
    _targetKwh = newGoal;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('energy_goal', newGoal);
  }

  void updateUsage(double kwh) {
    _currentUsageKwh = kwh;
    notifyListeners();
  }
}