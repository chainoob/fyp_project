import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    _repo.authStateChanges.listen((user) async {
      _currentUser = user;
      if (user != null) {
        // Sync role directly from the user object emitted by the reactive stream
        _role = user.role; 
        initFcm();
      } else {
        _role = null;
      }
      notifyListeners();
    }, onError: (e) => AppLog.error("Auth State Listener Failure", e));
  }

  Users? get currentUser => _currentUser;
  GoogleSignInAccount? get pendingGoogleUser => _pendingGoogleUser;
  bool get loggedIn => _currentUser != null;
  bool get isStaff => (_role ?? _currentUser?.role) == 'staff';
  bool get isLoading => _isLoading;

  Future<void> initFcm() async {
    if (_currentUser == null) return;

    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await messaging.getToken();
        if (token != null) {
          await _repo.saveFcmToken(_currentUser!.uid, token);
        }
      }
    } catch (e, stack) {
      AppLog.error("FCM Initialization", e, stack);
    }
  }

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
      } else {
        _pendingGoogleUser = googleUser;
      }
      return userExists;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut(BuildContext context) async {
    // Graceful stream termination across all active providers
    context.read<ApplianceProvider>().clear();
    context.read<GoalProvider>().clear();
    context.read<EnergyProvider>().clear();

    await _repo.signOut();
    _currentUser = null;
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

class ApplianceProvider extends ChangeNotifier {
  final EnergyRepository _repo;
  List<Appliance> _appliances = [];
  List<MapEntry<String, Appliance>> _pendingQueue = [];
  StreamSubscription? _streamSub;

  ApplianceProvider(this._repo);

  List<Appliance> get appliances => _appliances;
  List<MapEntry<String, Appliance>> get pendingQueue => _pendingQueue;

  final ApiService _apiService = ApiService();
  bool _isAnalyzing = false;
  Map<String, dynamic>? _latestReportData;

  bool get isAnalyzing => _isAnalyzing;
  Map<String, dynamic>? get latestReportData => _latestReportData;

  Future<void> fetchDisaggregationAnalysis({
    required String userId,
    required List<double> readings,
    required Map<String, double?> manualOverrides,
    required List<String> registeredAppliances, 
  }) async {
    _isAnalyzing = true;
    notifyListeners();

    try {
      final data = await _apiService.triggerDisaggregation(
        userId: userId,
        readings: readings,
        manualOverrides: manualOverrides,
        registeredAppliances: registeredAppliances, 
      );
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
    _streamSub?.cancel();
    _streamSub = _repo.getAppliancesStream(userId).listen((data) {
      _appliances = data;
      notifyListeners();
    }, onError: (e) => AppLog.error("Appliance Stream Failure", e));
  }

  void subscribeToQueue() {
    _streamSub?.cancel();
    _streamSub = _repo.getPendingVerificationStream().listen((data) {
      _pendingQueue = data;
      notifyListeners();
    }, onError: (e) => AppLog.error("Verification Stream Failure", e));
  }

  void clear() {
    _streamSub?.cancel();
    _appliances = [];
    _pendingQueue = [];
    notifyListeners();
  }

  Future<void> add(String name, String type, int watts, String room) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not logged in");

    final String safeUid = user.uid;
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

    await _repo.saveAppliance(safeUid, newAppliance);
    notifyListeners();
  }

  Future<void> delete(String userId, String appId) async {
    await _repo.deleteAppliance(userId, appId);
  }

 Future<void> approve(String userId, String appId, String ignoredUiUnitId) async {
    // Execute state mutation immediately.
    await _repo.updateApplianceStatus(userId, appId, 'active');

    final int remainingPending = _pendingQueue
        .where((entry) => entry.key == userId && entry.value.id != appId)
        .length;

    if (remainingPending == 0) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        final String? targetUnitId = userDoc.data()?['assignedUnitId'];

        if (targetUnitId != null && targetUnitId.isNotEmpty) {
          final now = DateTime.now();
          
          _apiService.seedSyntheticReddData(
            targetUnitId, 
            month: now.month, 
            year: now.year
          ).catchError((error) {
            debugPrint("Telemetry generation background task failed: $error");
          });
        } else {
          debugPrint("Abort generation: Student lacks physical unit assignment.");
        }
      } catch (e) {
        debugPrint("Unit resolution failed: $e");
      }
    }
  }

  Future<void> reject(String userId, String appId) async =>
      await _repo.updateApplianceStatus(userId, appId, 'rejected');

  Future<String> getStudentName(String uid) async {
    return await _repo.getStudentDisplayId(uid);
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
    }, onError: (e) => AppLog.error("Student Goal Stream Failure", e));
  }

  void subscribeToCampus() {
    _isCampusMode = true;
    _currentUserId = null;
    _sub?.cancel();

    _sub = _repo.getCampusGoalStream().listen((data) {
      _target = (data['monthlyGoal'] ?? 5000).toDouble(); 
      _current = (data['totalUsage'] ?? 0).toDouble();
      notifyListeners();
    }, onError: (e) => AppLog.error("Campus Goal Stream Failure", e));
  }

  void clear() {
    _sub?.cancel();
    _target = 0;
    _current = 0;
    _currentUserId = null;
    notifyListeners();
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

  Future<void> triggerAggregation({
    required String scope,
    required int month,
    required int year,
    String? blockId,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _repo.triggerAggregation(
        scope: scope,
        month: month,
        year: year,
        blockId: blockId,
      );
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
        if (scope.toLowerCase() == 'campus' || (scope.toLowerCase() == 'block' && unitId == null)) {
          await triggerAggregation(
            scope: scope,
            month: month,
            year: year,
            blockId: blockId,
          );
          
          return await _repo.fetchEnergyReport(
            scope: scope, 
            month: month, 
            year: year,
            blockId: blockId,
            unitId: unitId
          );
        }
        rethrow;
      }
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
  
  StreamSubscription? _asyncPipelineSub; 

  bool isLoading = true;
  bool isProcessingAI = false;
  String? errorMessage;

  Map<String, double?> manualOverrides = {};

  EnergyProvider(this._repository);

  Map<String, double> get applianceBreakdown => currentReport?.applianceBreakdown ?? {};

  void updateManualOverride(String applianceName, bool isOn) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    manualOverrides[applianceName] = isOn ? 1.0 : 0.0;
    if (uid != null) {
      _repository.saveManualOverrides(uid, manualOverrides);
    }
    notifyListeners();
  }

  void syncManualOverrides(Map<String, double?> overrides) {
    manualOverrides = Map<String, double?>.from(overrides);
    notifyListeners();
  }

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
      final errorStr = e.toString();
      if (errorStr.contains("Analysis data unavailable") || 
          errorStr.contains("Awaiting staff bill submission") ||
          errorStr.contains("No unit data found")) {
        errorMessage = null;
      } else {
        errorMessage = errorStr;
      }
      currentReport = null;
    } finally { 
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> runDisaggregation(
    String providedId, 
    String billId, 
    double totalBill, {
    required String scope,
    required int month,
    required int year,
    String? telemetrySourceId, 
    String? blockId,
  }) async {
    isProcessingAI = true;
    errorMessage = null;
    notifyListeners(); 

    try {
      final context = {
        'userId': providedId,
        'telemetrySourceId': telemetrySourceId ?? providedId, 
        'totalBill': totalBill,
        'month': month, 
        'year': year,  
        'scope': scope,
        'trainModel': false, 
        'blockId': blockId,
      };

      _asyncPipelineSub?.cancel(); 

      await _repository.triggerDisaggregation(providedId, context);
      
      await Future.delayed(const Duration(milliseconds: 1500));
      
      await loadReport(
        scope: scope,
        month: month,
        year: year,
        unitId: providedId,
      );
      
    } catch (e, stack) {
      errorMessage = e.toString();
      AppLog.error("Disaggregation Trigger Error", e, stack);
      rethrow;
    } finally {
      isProcessingAI = false;
      notifyListeners();
    }
  }

  Future<void> submitFeedback({
    required String userId,
    required String applianceName,
    required bool actualState,
    required bool predictedState,
  }) async {
    try {
      await _repository.sendFeedback(
        userId: userId,
        applianceName: applianceName,
        actualState: actualState,
        predictedState: predictedState,
      );
    } catch (e, stack) {
      AppLog.error("Feedback Loop Failure", e, stack);
      rethrow;
    }
  }

  void clear() {
    _asyncPipelineSub?.cancel();
    currentReport = null;
    manualOverrides = {};
    notifyListeners();
  }

  @override
  void dispose() {
    _asyncPipelineSub?.cancel();
    super.dispose();
  }
}