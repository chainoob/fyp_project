import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
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
 Future<void> completeGoogleProfile(Map<String, dynamic> additionalData) async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("No authenticated user found");

      await _repo.saveUserProfile(user.uid, additionalData);

      _pendingGoogleUser = null; 
      await fetchUserRole();     
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

  Future<void> linkPassword(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user != null && user.email != null) {
      try {
        AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!, 
          password: password
        );
        
        await user.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        // Ignore if already linked, otherwise rethrow to UI
        if (e.code != 'provider-already-linked') {
          rethrow;
        }
      }
    }
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

  Future<String> getStudentName(String uid) async {
      return _repo.getStudentDisplayId(uid); // Assuming your repo is stored in _repository
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}

class GoalProvider with ChangeNotifier {
  final EnergyRepository _repo;
  StreamSubscription? _sub;
  GoalProvider(this._repo);

  double _target = 0;
  double _current = 0;
  
  // State to track which mode we are in (for the 'setGoal' function)
  bool _isCampusMode = false; 
  String? _currentUserId;

  double get target => _target;
  double get current => _current;
  
  double get progress => _target > 0 ? (_current / _target).clamp(0.0, 1.0) : 0.0;
  bool get isOverBudget => _target > 0 && _current > _target;

  // --- MODE A: STUDENT ---
  void subscribeToStudent(String uid) {
    _isCampusMode = false;
    _currentUserId = uid;
    _sub?.cancel();

    _sub = _repo.getStudentGoalStream(uid).listen((data) {
      _target = (data['energyGoal'] ?? 0).toDouble();
      _current = (data['currentUsage'] ?? 0).toDouble();
      notifyListeners();
    });
  }

  // --- MODE B: STAFF ---
  void subscribeToCampus() {
    _isCampusMode = true;
    _currentUserId = null;
    _sub?.cancel();

    _sub = _repo.getCampusGoalStream().listen((data) {
      _target = (data['monthlyGoal'] ?? 5000).toDouble(); 
      _current = (data['totalUsage'] ?? 0).toDouble();
      notifyListeners();
    });
  }

  // --- SHARED UPDATE LOGIC ---
  Future<void> setGoal(double newGoal) async {
    if (_isCampusMode) {
      await _repo.updateCampusGoal(newGoal);
    } else if (_currentUserId != null) {
      await _repo.updateStudentGoal(_currentUserId!, newGoal);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class ReportProvider extends ChangeNotifier {
  final EnergyRepository _repo;

  // State
  List<Map<String, dynamic>> _blocks = [];
  List<Map<String, dynamic>> _units = [];
  bool _isLoading = false;
  
  // Getters
  List<Map<String, dynamic>> get blocks => _blocks;
  List<Map<String, dynamic>> get units => _units;
  bool get isLoading => _isLoading;

  ReportProvider(this._repo);

  Future<void> loadInitialData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _blocks = await _repo.fetchBlocks();
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUnitsForBlock(String blockId) async {
    _isLoading = true;
    notifyListeners();
    try {
      _units = await _repo.fetchUnits(blockId);
    } catch (e) {
      debugPrint(e.toString());
      _units = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearUnits() {
    _units = [];
    notifyListeners();
  }

  Future<EnergyReportData?> generateReport({
    required String scope,
    required int month,
    required int year,
    String? blockId,
    String? unitId,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final data = await _repo.fetchEnergyReport(
        scope: scope, 
        month: month, 
        year: year,
        blockId: blockId,
        unitId: unitId
      );
      return data;
    } catch (e) {
      debugPrint("Report Generation Error: $e");
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}