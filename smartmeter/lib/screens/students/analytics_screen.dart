import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/models/app_model.dart';
import 'package:smartmeter/services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _touchedIndex = -1; 
  DateTime _selectedDate = DateTime.now();

  ForecastResponse? _forecast;
  bool _isLoadingForecast = true;
  // ignore: unused_field
  String? _forecastError;
  final ApiService _apiService = ApiService();

  final Color _bgDark = const Color(0xFF121212);      
  final Color _cardDark = const Color(0xFF1E1E1E);    
  final Color _textPrimary = Colors.white;            
  final Color _textSecondary = Colors.white54;        
  final Color _cCyan = const Color(0xFF00E5FF);  

  @override
  void initState() {
    super.initState();
    _fetchForecastData(_selectedDate.month, _selectedDate.year);
  }

 Future<void> _fetchForecastData(int month, int year) async {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      if (mounted) setState(() => _isLoadingForecast = false);
      return;
    }

    try {
      final result = await _apiService.getEnergyForecast(user.uid, month, year);
      if (mounted) {
        setState(() {
          _forecast = result;
          _isLoadingForecast = false;
          _forecastError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _forecast = null;
          _isLoadingForecast = false;
          _forecastError = e.toString();
        });
      }
    }
  }

  void _fetchHistoricalData() {
    final user = context.read<AppAuthProvider>().currentUser;
    if (user != null) {
      context.read<EnergyProvider>().loadReport(
        scope: 'Personal',
        month: _selectedDate.month,
        year: _selectedDate.year,
        unitId: user.uid,
      );
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + offset);
      _isLoadingForecast = true;
      _forecast = null;
    });
    _fetchHistoricalData(); 
    _fetchForecastData(_selectedDate.month, _selectedDate.year);
  }

  @override
  Widget build(BuildContext context) {
    final energyProvider = context.watch<EnergyProvider>();
    final applianceProvider = context.watch<ApplianceProvider>();

    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        title: Text("Energy Analysis", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)), 
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textPrimary),
      ),
      body: _buildBody(energyProvider, applianceProvider),
    );
  }

  Widget _buildBody(EnergyProvider provider, ApplianceProvider applianceProvider) {
    if (provider.isLoading || provider.isProcessingAI) {
      return Center(child: CircularProgressIndicator(color: _cCyan));
    }

    final staticReport = provider.currentReport;
    final double targetEnergyGoal = 300.0; 

    final Map<String, String> nameToTypeMap = {};
    for (var app in applianceProvider.appliances) {
      nameToTypeMap[app.name.toLowerCase().trim()] = app.type;
    }

    final Map<String, double> groupedBreakdown = {};
    final Map<String, double> groupedBenchmark = {};
    List<MapEntry<String, double>> chartEntries = [];

    if (staticReport != null) {
      staticReport.applianceBreakdown.forEach((key, value) {
        final String keyLower = key.toLowerCase().trim();
        final String type = nameToTypeMap[keyLower] ?? key;
        final String normalizedType = type.isNotEmpty 
            ? (type[0].toUpperCase() + type.substring(1)) 
            : 'Unknown';
        groupedBreakdown[normalizedType] = (groupedBreakdown[normalizedType] ?? 0.0) + value;
      });

      staticReport.benchmarkBreakdown.forEach((key, value) {
        final String keyLower = key.toLowerCase().trim();
        final String type = nameToTypeMap[keyLower] ?? key;
        final String normalizedType = type.isNotEmpty 
            ? (type[0].toUpperCase() + type.substring(1)) 
            : 'Unknown';
        groupedBenchmark[normalizedType] = (groupedBenchmark[normalizedType] ?? 0.0) + value;
      });

      chartEntries = groupedBreakdown.entries
          .map((e) => MapEntry(e.key, e.value.toDouble()))
          .toList();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthSelector(),
          const SizedBox(height: 24),

          if (_isLoadingForecast)
            const Center(child: CircularProgressIndicator())
          else if (_forecast != null)
            _buildForecastCard(_forecast!, targetEnergyGoal)
          else
            Card(
              color: _cardDark,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Forecast data currently unavailable. Check network connection.', style: TextStyle(color: _textSecondary)),
              ),
            ),
          
          const SizedBox(height: 24),

          if (staticReport != null) ...[
            if (staticReport.anomalies.isNotEmpty) ...[
              _buildAnomaliesCard(staticReport.anomalies),
              const SizedBox(height: 24),
            ],

            _buildSectionTitle("AI Prediction Verification"),
            const SizedBox(height: 12),
            
            _buildFeedbackCard(
              staticReport.applianceBreakdown.keys.toList()
            ), 
            
            const SizedBox(height: 24),

            _buildBreakdownCard(
              staticReport.summary.totalConsumption, 
              chartEntries, 
              staticReport.summary.keyIssue,
              groupedBenchmark,
            ),
            const SizedBox(height: 24),
          ] else ...[
             Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Text(
                  "Historical analysis data unavailable for this month.\nAwaiting disaggregation results.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textSecondary),
                ),
              ),
            ),
          ],

          _buildSectionTitle("24h Load Profile"),
          const SizedBox(height: 12),
          _buildHourlyTrendCard(
            (staticReport?.hourlyUsage ?? {}).isNotEmpty 
                ? staticReport!.hourlyUsage 
                : (_forecast?.mcmcHourlyProfile ?? {})
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textPrimary),
    );
  }

  Widget _buildAnomaliesCard(List<String> anomalies) {
    return Card(
      color: const Color(0xFF311B1B), 
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.redAccent, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                const SizedBox(width: 12),
                Text(
                  "Anomalous Activity Detected",
                  style: TextStyle(color: Colors.redAccent.shade100, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "The AI engine has identified energy signatures for unregistered high-load appliances in your loop:",
              style: TextStyle(color: _textPrimary.withAlpha(204), fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: anomalies.map((a) => Chip(
                label: Text(a, style: const TextStyle(fontSize: 11, color: Colors.white)),
                backgroundColor: Colors.redAccent.withAlpha(51),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(51), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: _textPrimary),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            DateFormat('MMMM yyyy').format(_selectedDate),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: _textPrimary),
            onPressed: _selectedDate.month == DateTime.now().month && _selectedDate.year == DateTime.now().year ? null : () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, String percentage) {
    return Row(
      children: [
        CircleAvatar(radius: 4, backgroundColor: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textPrimary))),
        Text(percentage, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textPrimary)),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message, style: TextStyle(color: _textSecondary, fontSize: 12)),
      ),
    );
  }

  Widget _buildBreakdownCard(double totalConsumption, List<MapEntry<String, double>> entries, String keyIssue, Map<String, double> benchmark) {
    if (entries.isEmpty || totalConsumption <= 0) {
      return _buildEmptyState("No disaggregation data available.");
    }

    final List<Color> palette = [
      const Color(0xFF00E5FF),
      const Color(0xFF7C4DFF),
      const Color(0xFF1DE9B6),
      const Color(0xFFFF4081),
      const Color(0xFFFFC400),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
      color: _cardDark, 
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  height: 120,
                  width: 120,
                  child: PieChart(
                      PieChartData(
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        sections: entries.asMap().entries.map((e) {
                          final index = e.key;
                          final entry = e.value;
                          final isTouched = index == _touchedIndex;
                          final radius = isTouched ? 40.0 : 30.0;
                          
                          return PieChartSectionData(
                            color: palette[index % palette.length],
                            value: entry.value,
                            title: '', 
                            radius: radius,
                          );
                        }).toList(),
                        pieTouchData: PieTouchData(
                          touchCallback: (FlTouchEvent event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions || 
                                  pieTouchResponse == null || 
                                  pieTouchResponse.touchedSection == null) {
                                _touchedIndex = -1;
                                return;
                              }
                              _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entries.asMap().entries.map((e) {
                      final index = e.key;
                      final entry = e.value;
                      final percentage = totalConsumption > 0 ? (entry.value / totalConsumption) * 100 : 0.0;
                      
                      final benchmarkVal = benchmark[entry.key] ?? 0.0;
                      final bool isOverBenchmark = entry.value > benchmarkVal && benchmarkVal > 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLegendItem(
                              palette[index % palette.length], 
                              entry.key, 
                              "${percentage.toStringAsFixed(1)}%"
                            ),
                            if (benchmarkVal > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 16.0, top: 2),
                                child: Text(
                                  isOverBenchmark ? "↑ High usage" : "↓ Optimal usage",
                                  style: TextStyle(
                                    fontSize: 10, 
                                    color: isOverBenchmark ? Colors.orangeAccent : Colors.greenAccent,
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                keyIssue, 
                style: TextStyle(fontSize: 12, color: _textSecondary, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackCard(List<String> applianceNames) {
    if (applianceNames.isEmpty) return const SizedBox.shrink();
    
    return Card(
      color: _cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Was the AI accurate?",
              style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Help improve the disaggregation engine by flagging incorrect appliance states.",
              style: TextStyle(color: _textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: applianceNames.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return ActionChip(
                    label: Text(applianceNames[index], style: const TextStyle(fontSize: 11)),
                    backgroundColor: _cCyan.withAlpha(25),
                    side: BorderSide(color: _cCyan.withAlpha(51)),
                    onPressed: () => _showFeedbackDialog(applianceNames[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFeedbackDialog(String applianceName) {
    showDialog(
      context: context,
      builder: (context) {
        bool actualState = true;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: _cardDark,
              title: Text("Verify $applianceName", style: TextStyle(color: _textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "The AI predicted this appliance was ACTIVE during the recording period. Is this correct?",
                    style: TextStyle(color: _textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("NO", style: TextStyle(color: !actualState ? _cCyan : _textSecondary, fontWeight: FontWeight.bold)),
                      Switch(
                        value: actualState,
                        onChanged: (val) => setState(() => actualState = val),
                        activeThumbColor: _cCyan,
                      ),
                      Text("YES", style: TextStyle(color: actualState ? _cCyan : _textSecondary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("CANCEL", style: TextStyle(color: _textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final user = context.read<AppAuthProvider>().currentUser;
                    if (user != null) {
                      await context.read<EnergyProvider>().submitFeedback(
                        userId: user.uid,
                        applianceName: applianceName,
                        actualState: actualState,
                        predictedState: true,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Feedback synced with AI engine. Thank you!"))
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: _cCyan),
                  child: const Text("SUBMIT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHourlyTrendCard(Map<int, double> hourlyData) {
    if (hourlyData.isEmpty) {
      return Card(
        color: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const SizedBox(
          height: 200,
          width: double.infinity,
          child: Center(
            child: Text(
              "Insufficient temporal data.\nHourly vector missing from backend payload.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ),
      );
    }

    List<FlSpot> spots = [];
    double maxY = 0;

    hourlyData.forEach((hour, value) {
      spots.add(FlSpot(hour.toDouble(), value));
      if (value > maxY) maxY = value;
    });

    spots.sort((a, b) => a.x.compareTo(b.x));

    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "24h Synthetic Load Profile",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withAlpha(13), strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 6,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toInt()}:00', style: const TextStyle(color: Colors.white54, fontSize: 10));
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: maxY > 0 ? (maxY / 4).ceilToDouble() : 1,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          return Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.white54, fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 23,
                  minY: 0,
                  maxY: maxY * 1.2,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: const Color(0xFF00E5FF),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF00E5FF).withAlpha(38),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastCard(ForecastResponse forecast, double energyGoal) {
    final bool isOverBudget = forecast.estimatedEndOfMonthTotal > energyGoal;
    final Color statusColor = isOverBudget ? Colors.redAccent : Colors.greenAccent;
    final double estimatedCost = ReportSummary.calculateMalaysianTariffA(forecast.estimatedEndOfMonthTotal);

    return Card(
      color: _cardDark,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('30-Day Automated Forecast', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textPrimary)),
            const SizedBox(height: 12),
            Text('Current Usage: ${forecast.currentConsumption} kWh', style: TextStyle(color: _textSecondary)),
            Text('Projected Addition: +${forecast.projectedAddition} kWh', style: TextStyle(color: _textSecondary)),
            Text('Estimated Monthly Cost: RM ${estimatedCost.toStringAsFixed(2)}', style: TextStyle(color: _textSecondary)),
            const Divider(color: Colors.white12, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estimated Month Total:', style: TextStyle(fontWeight: FontWeight.w600, color: _textPrimary)),
                Text(
                  '${forecast.estimatedEndOfMonthTotal} kWh',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isOverBudget)
              const Text(
                'Warning: Projected to exceed energy budget.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}