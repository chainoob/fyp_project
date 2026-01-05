// ignore_for_file: unused_field

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smartmeter/config/theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  int _touchedIndex = -1; // For Pie Chart interactivity

  // --- VARIABLES (To be populated by Backend) ---

  // 1. CMOEA Data (Appliance Breakdown)
  // Structure: {'name': String, 'value': double, 'color': Color}
  List<Map<String, dynamic>> _applianceData = [];

  // 2. Historical Data (Last 7 Days)
  List<FlSpot> _weeklyHistory = [];

  // 3. LSTM Forecast Data (Next 24 Hours)
  List<FlSpot> _forecastData = [];
  
  // 4. Prediction Summary
  double _predictedLoad = 0.0;
  String _forecastMessage = "Waiting for analysis...";

  @override
  void initState() {
    super.initState();
    _fetchCloudRunInsights();
  }

  Future<void> _fetchCloudRunInsights() async {
    // -------------------------------------------------------------------------
    // TODO: BACKEND INTEGRATION (Cloud Run - Python)
    // -------------------------------------------------------------------------
    // According to System Architecture [Section 2.1], the Inference Layer is
    // hosted on Cloud Run (Python) and accessed via REST API.
    //
    // 1. FETCH DISAGGREGATION (CMOEA Algorithm)
    //    Endpoint: POST /api/v1/disaggregate
    //    Input: Building-level consumption data (from Firestore)
    //    Action: Parse JSON response and populate '_applianceData'.
    //            Ensure you map categories to specific Colors.
    //
    // 2. FETCH FORECASTING (LSTM Neural Network)
    //    Endpoint: POST /api/v1/forecast
    //    Input: Last 24h sequence (from Firestore)
    //    Action: Parse JSON response to populate '_forecastData' (24 hourly points)
    //            and update '_predictedLoad' (total kWh).
    // -------------------------------------------------------------------------

    try {
      // TODO: Implement actual API calls here.
      // Example:
      // final disaggResponse = await http.post(Uri.parse('YOUR_CLOUD_RUN_URL/disaggregate'), body: ...);
      // final forecastResponse = await http.post(Uri.parse('YOUR_CLOUD_RUN_URL/forecast'), body: ...);

      if (mounted) {
        setState(() {
          // TODO: Assign parsed data to variables here
          // _applianceData = ...
          // _weeklyHistory = ...
          // _forecastData = ...
          // _predictedLoad = ...
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Cloud Run Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("AI Energy Analytics"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: const TextStyle(
            color: AppTheme.navyBlue, fontSize: 24, fontWeight: FontWeight.bold),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.ecoTeal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle("Real-Time Disaggregation (CMOEA)"),
                  const SizedBox(height: 8),
                  const Text(
                    "Breakdown of energy usage by appliance type.",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  
                  // --- PIE CHART ---
                  if (_applianceData.isEmpty)
                    _buildEmptyState("No disaggregation data available yet.")
                  else ...[
                    SizedBox(
                      height: 250,
                      child: PieChart(
                        PieChartData(
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
                          borderData: FlBorderData(show: false),
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          sections: _showingSections(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildLegend(),
                  ],

                  const SizedBox(height: 32),
                  _buildSectionTitle("Consumption Trends"),
                  const SizedBox(height: 16),
                  
                  // --- HISTORY LINE CHART ---
                  Container(
                    height: 250,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _weeklyHistory.isEmpty
                      ? _buildEmptyState("No historical data.")
                      : LineChart(_mainLineData(_weeklyHistory, Colors.blueAccent, "Last 7 Days")),
                  ),

                  const SizedBox(height: 32),
                  _buildSectionTitle("LSTM Forecast (Next 24h)"),
                  const SizedBox(height: 8),
                  const Text(
                    "Predicted load curve for the upcoming day.",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // --- FORECAST LINE CHART ---
                  Container(
                    height: 250,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.ecoTeal.withValues(alpha: 0.3)),
                    ),
                    child: _forecastData.isEmpty
                      ? _buildEmptyState("No forecast generated.")
                      : LineChart(_mainLineData(_forecastData, AppTheme.ecoTeal, "Predicted kWh")),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(message, style: const TextStyle(color: Colors.white24)),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  // --- CHART HELPERS ---

  Widget _buildLegend() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      children: _applianceData.map((data) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: data['color'], shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              data['name'],
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        );
      }).toList(),
    );
  }

  List<PieChartSectionData> _showingSections() {
    return List.generate(_applianceData.length, (i) {
      final isTouched = i == _touchedIndex;
      final fontSize = isTouched ? 20.0 : 14.0;
      final radius = isTouched ? 60.0 : 50.0;
      final data = _applianceData[i];

      return PieChartSectionData(
        color: data['color'],
        value: data['value'],
        title: '${data['value'].toInt()}%',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });
  }

  LineChartData _mainLineData(List<FlSpot> spots, Color color, String label) {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: (value, meta) {
              if (value % 2 != 0) return const SizedBox.shrink(); 
              return Text(
                value.toInt().toString(), 
                style: const TextStyle(color: Colors.grey, fontSize: 10)
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) => Text(
              value.toStringAsFixed(0),
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
            reservedSize: 30,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: spots.isEmpty ? 0 : spots.last.x,
      minY: 0,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: color.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}