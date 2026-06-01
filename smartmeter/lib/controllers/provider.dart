import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:smartmeter/models/app_model.dart';
import 'package:smartmeter/models/disaggregation_response.dart';
import 'package:smartmeter/services/api_service.dart';
import 'package:smartmeter/services/disaggregation_service.dart';
import 'package:smartmeter/services/energy_repo.dart';
import 'package:smartmeter/services/iot_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
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
        initFcm();
      }
      notifyListeners();
    });
  }

  Users? get currentUser => _currentUser;
  GoogleSignInAccount? get pendingGoogleUser => _pendingGoogleUser;
  bool get loggedIn => _currentUser != null;
  bool get isStaff => _role == 'staff';
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
    });
  }

  void subscribeToQueue() {
    _streamSub?.cancel();
    _streamSub = _repo.getPendingVerificationStream().listen((data) {
      _pendingQueue = data;
      notifyListeners();
    });
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

  Future<void> approve(String userId, String appId) async {
    await _repo.updateApplianceStatus(userId, appId, 'active');
    
    final int remainingPending = _pendingQueue
        .where((entry) => entry.key == userId && entry.value.id != appId)
        .length;

    if (remainingPending == 0) {
      final now = DateTime.now();
      await _apiService.seedSyntheticReddData(userId, month: now.month, year: now.year);
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

  Future<void> triggerAggregation({
    required String scope,
    required int month,
    required int year,
    String? blockId,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Fetch raw underlying unit results directly from the ML output collection
      final snapshot = await FirebaseFirestore.instance
          .collection('disaggregation_results')
          .where('month', isEqualTo: month)
          .where('year', isEqualTo: year)
          .get();

      if (snapshot.docs.isEmpty) {
        throw Exception("No unit data found to compile. Staff must submit bills first.");
      }

      Map<String, double> aggBreakdown = {};
      double aggCarbon = 0.0;
      double aggCost = 0.0;
      double aggConsumption = 0.0; 
      Set<String> aggAnomalies = {};
      Map<String, double> aggHourly = {}; 

      bool processedAny = false;

      // 2. Loop through and mathematically fold the data together
      for (var doc in snapshot.docs) {
        final rawData = doc.data();
        
        // Skip already aggregated documents to avoid double-counting
        if (doc.id == 'aggregate' || rawData['userId'] == 'aggregate' || rawData['userId'] == blockId) continue;

        // Ensure Block level aggregation only calculates units inside that specific block
        if (scope.contains('Block') && rawData['blockId'] != blockId) continue;
        
        processedAny = true;
        final data = EnergyReportData.fromFirestore(doc);
        
        aggCarbon += data.carbonFootprint;
        aggCost += data.summary.totalCost;
        aggConsumption += data.summary.totalConsumption; 
        aggAnomalies.addAll(data.anomalies);
        
        data.applianceBreakdown.forEach((key, val) {
          aggBreakdown[key] = (aggBreakdown[key] ?? 0.0) + val;
        });

        data.hourlyUsage.forEach((hour, val) {
          aggHourly[hour.toString()] = (aggHourly[hour.toString()] ?? 0.0) + val;
        });
      }

      if (!processedAny) {
         throw Exception("No data matches the selected $scope criteria.");
      }

      final String lookupKey = (scope == 'Campus') ? 'aggregate' : blockId!;

      // 3. Commit the compiled master report to the main results collection
      await FirebaseFirestore.instance.collection('disaggregation_results').doc(lookupKey).set({
        'userId': lookupKey,
        'scope': scope,
        'month': month,
        'year': year,
        if (blockId != null) 'blockId': blockId,
        'carbonFootprint': aggCarbon,
        'breakdown': aggBreakdown,
        'anomalies': aggAnomalies.toList(),
        'hourlyUsage': aggHourly,
        'summary': {
          'totalConsumption': aggConsumption,
          'comparisonPercent': 0.0,
          'totalCost': aggCost,
          'keyIssue': aggAnomalies.isNotEmpty 
              ? "Critical: Anomalies detected across ${aggAnomalies.length} profiles." 
              : "Consumption nominal across all units.",
          'recommendations': ["Review high-load units identified in breakdown."]
        },
        'kpis': {
          'totalKwh': aggConsumption,
          'dailyAvgKwh': aggConsumption / 30,
          'totalCost': aggCost,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

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
  final DisaggregationService _mlService = DisaggregationService();

  EnergyReportData? currentReport;
  DisaggregationResponse? currentMlReport;
  
  final List<double> _liveReadings = [];
  IoTTelemetrySource? _iotSource;
  StreamSubscription? _telemetrySub;
  StreamSubscription? _statusSub;
  StreamSubscription? _asyncPipelineSub; 

  bool isLoading = true;
  bool isProcessingAI = false;
  bool isProcessingML = false;
  bool isConnected = false;
  String? errorMessage;

  Map<String, double?> manualOverrides = {};

  String? _telemetryUserId;
  String? _targetReportId;

  EnergyProvider(this._repository);

  List<double> get liveReadings => _liveReadings;
  Map<String, double> get applianceBreakdown => currentMlReport?.data.breakdown ?? {};

  void updateManualOverride(String applianceName, bool isOn) {
    manualOverrides[applianceName] = isOn ? 1.0 : 0.0;
    notifyListeners();
    if (_liveReadings.length >= 3) {
      fetchRealTimeDisaggregation(aggregateReadings: _liveReadings);
    }
  }

  void subscribeToTelemetry(String userId, {String? targetReportId}) {
    _telemetryUserId = userId;
    _targetReportId = targetReportId;
    
    _telemetrySub?.cancel();
    _statusSub?.cancel();
    _iotSource?.dispose();

    _iotSource = FirebaseTelemetrySource(
      userId, 
      _repository.getLiveReadingsStream(userId)
    );

    _statusSub = _iotSource!.connectionStatus.listen((status) {
      isConnected = status;
      notifyListeners();
    });

    _telemetrySub = _iotSource!.wattageStream.listen((wattage) {
      if (_liveReadings.length >= 10) _liveReadings.removeAt(0);
      _liveReadings.add(wattage);
      notifyListeners();
      
      if (_liveReadings.length >= 4) {
        fetchRealTimeDisaggregation(aggregateReadings: _liveReadings);
      }
    });
  }

  Future<EnergyReportData> _aggregateCampusData(int month, int year) async {
    // Check if a pre-compiled aggregate report exists first
    try {
      final String docId = "aggregate_${month}_$year";
      final existingAgg = await FirebaseFirestore.instance
          .collection('disaggregation_results')
          .doc(docId)
          .get();
      
      if (existingAgg.exists) {
        return EnergyReportData.fromFirestore(existingAgg);
      }
    } catch (_) {}

    final snapshot = await FirebaseFirestore.instance
        .collection('disaggregation_results')
        .where('userId', isEqualTo: 'aggregate')
        .where('month', isEqualTo: month)
        .where('year', isEqualTo: year)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return EnergyReportData.fromFirestore(snapshot.docs.first);
    }

    // Manual fall-through aggregation if no pre-compiled doc is found
    final allReports = await FirebaseFirestore.instance
        .collection('disaggregation_results')
        .where('month', isEqualTo: month)
        .where('year', isEqualTo: year)
        .get();

    if (allReports.docs.isEmpty) {
      throw Exception("Analysis data unavailable for aggregate ($month/$year). Awaiting staff bill submission.");
    }

    Map<String, double> aggBreakdown = {};
    double aggCarbon = 0.0;
    double aggCost = 0.0;
    double aggConsumption = 0.0; 
    Set<String> aggAnomalies = {};
    Map<int, double> aggHourly = {};

    for (var doc in allReports.docs) {
      final data = doc.data();
      // Skip already aggregated documents to avoid double-counting
      if (doc.id.contains('aggregate') || data['userId'] == 'aggregate') continue;
      
      final report = EnergyReportData.fromFirestore(doc);
      
      aggCarbon += report.carbonFootprint;
      aggCost += report.summary.totalCost;
      aggConsumption += report.summary.totalConsumption; 
      aggAnomalies.addAll(report.anomalies);
      
      report.applianceBreakdown.forEach((key, val) {
        aggBreakdown[key] = (aggBreakdown[key] ?? 0.0) + val;
      });

      report.hourlyUsage.forEach((hour, val) {
        aggHourly[hour] = (aggHourly[hour] ?? 0.0) + val;
      });
    }

    return EnergyReportData(
      id: 'aggregate',
      summary: ReportSummary(
        totalConsumption: aggConsumption,
        comparisonPercent: 0.0, 
        totalCost: aggCost,
        keyIssue: aggAnomalies.isNotEmpty 
            ? "Critical: Anomalies detected across ${aggAnomalies.length} profiles." 
            : "Campus consumption nominal.",
        recommendations: [], 
      ),
      kpis: ReportKPIs(
        totalKwh: aggConsumption,
        dailyAvgKwh: aggConsumption / 30,
        peakKwh: 0.0,
        peakTime: "N/A",
        totalCost: aggCost,
        changePercent: 0.0,
      ),
      carbonFootprint: aggCarbon,
      usageTrend: [],
      applianceBreakdown: aggBreakdown,
      benchmarkBreakdown: {}, 
      anomalies: aggAnomalies.toList(),
      hourlyUsage: aggHourly,
      costBreakdown: {},
    );
  }

  void subscribeToReport({
    required String scope,
    required int month,
    required int year,
    String? unitId,
    String? blockId,
  }) {
    _asyncPipelineSub?.cancel();
    
    final String lookupKey = unitId ?? blockId ?? 'aggregate';

    _asyncPipelineSub = FirebaseFirestore.instance
        .collection('disaggregation_results')
        .where('userId', isEqualTo: lookupKey)
        .where('month', isEqualTo: month)
        .where('year', isEqualTo: year)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            try {
              currentReport = EnergyReportData.fromFirestore(snapshot.docs.first);
              isLoading = false;
              errorMessage = null;
              notifyListeners();
            } catch (e, stack) {
              errorMessage = "Data mapping error: $e";
              isLoading = false;
              currentReport = null;
              AppLog.error("FATAL PARSE ERROR", e, stack);
              notifyListeners();
            }
          } else {
            if (scope.toLowerCase().contains('campus') || (scope.toLowerCase().contains('block') && unitId == null)) {
               loadReport(scope: scope, month: month, year: year, blockId: blockId, unitId: unitId);
            } else {
              // Retrieve transient real-time fallback data
              FirebaseFirestore.instance.collection('realtime_results')
                  .doc(lookupKey)
                  .get()
                  .then((doc) {
                    try {
                      if (doc.exists) {
                        currentReport = EnergyReportData.fromFirestore(doc);
                        errorMessage = null;
                      } else {
                        currentReport = null;
                      }
                    } catch (e, stack) {
                      errorMessage = "Fallback mapping error: $e";
                      currentReport = null;
                      AppLog.error("FATAL PARSE ERROR", e, stack);
                    }
                    isLoading = false;
                    notifyListeners();
                  }).catchError((e) {
                    errorMessage = "Fallback retrieval error: $e";
                    currentReport = null;
                    isLoading = false;
                    notifyListeners();
                  });
            }
          }
        }, onError: (e) {
          errorMessage = "Stream rejected: $e";
          isLoading = false;
          AppLog.error("FIRESTORE ERROR", e, null);
          notifyListeners();
        });
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
      if (scope.toLowerCase().contains('campus')) {
        currentReport = await _aggregateCampusData(month, year);
      } else if (scope.toLowerCase().contains('block') && unitId == null) {
        currentReport = await _repository.fetchEnergyReport(
          scope: scope,
          month: month,
          year: year,
          blockId: blockId,
        );
      } else {
        currentReport = await _repository.fetchEnergyReport(
          scope: scope,
          month: month,
          year: year,
          blockId: blockId,
          unitId: unitId,
        );
      }
    } catch (e) {
      // Don't set error if we're just waiting for data in a unit scope
      if (!scope.toLowerCase().contains('unit')) {
        errorMessage = e.toString();
      }
      currentReport = null;
    } finally { 
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> runDisaggregation(
    String userId, 
    String billId, 
    double totalBill, {
    required String scope,
    required int month,
    required int year,
    String? telemetrySourceId, 
  }) async {
    isProcessingAI = true;
    errorMessage = null;
    notifyListeners(); 

    try {
      final context = {
        'userId': userId,
        'telemetrySourceId': telemetrySourceId ?? userId, 
        'totalBill': totalBill,
        'month': month, 
        'year': year,  
        'scope': scope,
        'trainModel': false, 
      };

      _asyncPipelineSub?.cancel();
      
      _asyncPipelineSub = FirebaseFirestore.instance
          .collection('disaggregation_results')
          .where('userId', isEqualTo: userId)
          .where('month', isEqualTo: month)
          .where('year', isEqualTo: year)
          .snapshots()
          .listen((snapshot) async {
            if (snapshot.docs.isNotEmpty) {
              _asyncPipelineSub?.cancel(); 
              
              await loadReport(
                scope: scope,
                month: month,
                year: year,
                unitId: userId,
              );
              
              isProcessingAI = false;
              notifyListeners();
            }
          }, onError: (error) {
            isProcessingAI = false;
            errorMessage = "Data pipeline synchronization dropped.";
            notifyListeners();
          });

      await _repository.triggerDisaggregation(userId, context);
      
    } catch (e, stack) {
      _asyncPipelineSub?.cancel();
      isProcessingAI = false;
      errorMessage = e.toString();
      AppLog.error("Disaggregation Trigger Error", e, stack);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> fetchRealTimeDisaggregation({
    required List<double> aggregateReadings,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String effectiveId = _targetReportId ?? user.uid;
    final String cacheKey = "ml_cache_${effectiveId}_${DateTime.now().hour}";
    final prefs = await SharedPreferences.getInstance();

    final String? cachedData = prefs.getString(cacheKey);
    if (cachedData != null && manualOverrides.isEmpty) {
      currentMlReport = DisaggregationResponse.fromJson(jsonDecode(cachedData));
      notifyListeners();
      return;
    }

    isProcessingML = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await _mlService.fetchDisaggregation(
        targetId: _targetReportId,
        aggregateReadings: aggregateReadings,
        manualOverrides: manualOverrides,
      );
      
      currentMlReport = response;
      if (manualOverrides.isEmpty) {
        await prefs.setString(cacheKey, jsonEncode(response.toJson()));
      }
    } catch (e, stack) {
      errorMessage = "Real-time disaggregation tracking failed.";
      AppLog.error("ML Cloud Run Pipeline Fetch Failure", e, stack);
      currentMlReport = null;
    } finally {
      isProcessingML = false;
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

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _asyncPipelineSub?.cancel();
    super.dispose();
  }
}