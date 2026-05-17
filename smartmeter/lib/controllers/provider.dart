import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:smartmeter/models/app_model.dart';
import 'package:smartmeter/services/api_service.dart';
import 'package:smartmeter/services/energy_repo.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:smartmeter/utils/logger.dart';

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

  Future<void> signOut() async {
    await _repo.signOut();
    _role = null;
    notifyListeners();
  }

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
        if (e.code != 'provider-already-linked') {
          rethrow;
        }
      }
    }
  }
}

// smartmeter/lib/providers/appliance_provider.dart

class ApplianceProvider extends ChangeNotifier {
  final EnergyRepository _repo;
  List<Appliance> _appliances = [];
  
  // Stores the mapped queue data for staff verification.
  List<MapEntry<String, Appliance>> _pendingQueue = [];
  StreamSubscription? _streamSub;

  ApplianceProvider(this._repo);

  List<Appliance> get appliances => _appliances;
  
  // Provides access to the grouped queue entries.
  List<MapEntry<String, Appliance>> get pendingQueue => _pendingQueue;

  final ApiService _apiService = ApiService();
  bool _isAnalyzing = false;
  Map<String, dynamic>? _latestReportData;

  bool get isAnalyzing => _isAnalyzing;
  Map<String, dynamic>? get latestReportData => _latestReportData;

  Future<void> fetchDisaggregationAnalysis({
    required String userId,
    required List<double> readings,
  }) async {
    _isAnalyzing = true;
    notifyListeners();

    try {
      // High-level: Dispatch asynchronous telemetry block to Cloud Run infrastructure.
      final data = await _apiService.triggerDisaggregation(
        userId: userId,
        aggregateReadings: readings,
      );
      
      // Developer Expectation: Store raw data map locally or parse directly into model state here.
      _latestReportData = data;
    } catch (e) {
      _latestReportData = null;
      rethrow;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  void subscribeToUser(String userId) {
    // Synchronizes the local appliance list with the user's specific subcollection.
    _streamSub?.cancel();
    _streamSub = _repo.getAppliancesStream(userId).listen((data) {
      _appliances = data;
      notifyListeners();
    });
  }

  void subscribeToQueue() {
    // Listens to the global pending collection and stores the UID/Appliance pairs.
    _streamSub?.cancel();
    _streamSub = _repo.getPendingVerificationStream().listen((data) {
      _pendingQueue = data;
      notifyListeners();
    });
  }

Future<void> add(String name, String type, int watts, String room) async {
  // High-level: Auth check using your existing internal logic.
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception("User not logged in");

  final String safeUid = user.uid;

  // Developer Expectation: Calculate HMM profile locally to avoid backend bootstrap errors.
  final List<double> calculatedStates = (type == 'Fan') 
      ? [0.0, watts * 0.6, watts.toDouble()] 
      : [0.0, watts.toDouble()];
      
  final int calculatedMaxIndex = calculatedStates.length - 1;

  final newAppliance = Appliance(
    id: '', 
    name: name,
    type: type,           
    location: room,       
    wattage: watts.toDouble(),
    probDay: 0.1,
    probNight: 0.1,
    maxDurationHr: 1.0,
    status: 'pending',     
    states: calculatedStates,
    maxStateIndex: calculatedMaxIndex,
  );

  // High-level: Persist via your existing repository pattern.
  await _repo.saveAppliance(safeUid, newAppliance);
  
  notifyListeners();
}

  Future<void> delete(String userId, String appId) async {
    // Removes the appliance from the database.
    await _repo.deleteAppliance(userId, appId);
  }

  Future<void> approve(String userId, String appId) async =>
      await _repo.updateApplianceStatus(userId, appId, 'active');

  Future<void> reject(String userId, String appId) async =>
      await _repo.updateApplianceStatus(userId, appId, 'rejected');

  Future<String> getStudentName(String uid) async {
    // Resolves student UID to a display name or ID for staff views.
    return await _repo.getStudentDisplayId(uid);
  }

  @override
  void dispose() {
    // Cleans up active streams to prevent memory leaks and redundant updates.
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
  
  bool _isCampusMode = false; 
  String? _currentUserId;

  double get target => _target;
  double get current => _current;
  
  double get progress => _target > 0 ? (_current / _target).clamp(0.0, 1.0) : 0.0;
  bool get isOverBudget => _target > 0 && _current > _target;

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

  List<Map<String, dynamic>> _blocks = [];
  List<Map<String, dynamic>> _units = [];
  bool _isLoading = false;
  
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

class EnergyProvider extends ChangeNotifier {
  final EnergyRepository _repository;

  EnergyReportData? currentReport;
  bool isLoading = true;
  bool isProcessingAI = false;
  String? errorMessage;

  EnergyProvider(this._repository);

  // Read Pipeline
  Future<void> loadReport({
    required String scope,
    required int month,
    required int year,
    String? blockId,
    String? unitId,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      currentReport = await _repository.fetchEnergyReport(
        scope: scope,
        month: month,
        year: year,
        blockId: blockId,
        unitId: unitId,
      );
    } catch (e) {
      errorMessage = e.toString();
      currentReport = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Write/Trigger Pipeline
  Future<void> runDisaggregation(String userId, String billId, double totalBill, {
    required String scope,
    required int month,
    required int year,
  }) async {
    isProcessingAI = true;
    errorMessage = null;
    notifyListeners();

    try {
      // High-level: Construct the context map to match the Repository and Cloud Function contract.
      final context = {
        'billId': billId,
        'totalBill': totalBill,
        'month': month.toString(),
        'year': year,
        'scope': scope,
        'trainModel': false, 
      };

      // Developer Expectation: This calls the Firebase 'onCall' function.
      await _repository.triggerDisaggregation(userId, context);
    
      
    } catch (e, stack) {
      errorMessage = "AI Execution Failed: See logs for details.";
      AppLog.error("Disaggregation Trigger", e, stack);
    } finally {
      isProcessingAI = false;
      notifyListeners();
    }
  }
}