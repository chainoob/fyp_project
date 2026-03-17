import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  int _touchedIndex = -1; 
  DateTime _selectedDate = DateTime.now();

  // --- VARIABLES (To be populated by Backend) ---
  List<Map<String, dynamic>> _applianceData = [];
  List<FlSpot> _weeklyHistory = [];
  List<FlSpot> _forecastData = [];
  double _predictedLoad = 0.0;
  double _currentLoad = 0.0; 
  String _analysisTip = ""; // Holds the dynamic advice string

  // --- DARK THEME COLORS ---
  final Color _bgDark = const Color(0xFF121212);      
  final Color _cardDark = const Color(0xFF1E1E1E);    
  final Color _textPrimary = Colors.white;            
  final Color _textSecondary = Colors.white54;        
  
  // --- CHART COLORS ---
  final Color _cCyan = const Color(0xFF00E5FF);       
  final Color _cGreen = const Color(0xFF00E676);      
  final Color _cAmber = const Color(0xFFFFC400);      
  final Color _cPurple = const Color(0xFFD500F9);     

  @override
  void initState() {
    super.initState();
    _fetchCloudRunInsights();
  }

  /// Updates the currently selected month and triggers a data refresh.
  void _changeMonth(int offset) {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + offset);
      _isLoading = true; 
    });
    _fetchCloudRunInsights(); 
  }

  /// Fetches analytics data from the Cloud Run Python endpoint.
  Future<void> _fetchCloudRunInsights() async {
    // -------------------------------------------------------------------------
    // TODO: BACKEND INTEGRATION (Cloud Run - Python)
    // -------------------------------------------------------------------------
    // 1. Call your Cloud Run Endpoint: POST /api/v1/analyze
    // 2. Pass userId and _selectedDate as parameters.
    // 3. Receive JSON containing breakdown, history, forecast, and advice string.
    // -------------------------------------------------------------------------
    
    // Simulating API delay
    await Future.delayed(const Duration(seconds: 1));

    try {
      if (mounted) {
        setState(() {
          // ===================================================================
          // START MOCK DATA (DELETE THIS BLOCK WHEN API IS READY)
          // ===================================================================
          
          // 1. Breakdown (FHMM)
          // TODO: Map API response to this structure.
          _applianceData = [
            {'name': 'Fan', 'value': 30.0, 'color': _cGreen},
            {'name': 'Laptop', 'value': 20.0, 'color': _cAmber},
            {'name': 'Lamp', 'value': 10.0, 'color': Colors.white24},
          ];

          // 2. Analysis Tip
          // TODO: Fetch this string dynamically based on the highest energy consumer
          _analysisTip = "Iron has the highest consumption. Consider turning it off when not in use.";

          // 3. History Trend (Weekly/Monthly)
          // TODO: Convert Firestore Timestamps/Values to FlSpot(x, y)
          _weeklyHistory = [
            const FlSpot(1, 3), const FlSpot(5, 4), const FlSpot(10, 3.5),
            const FlSpot(15, 6), const FlSpot(20, 4.5), const FlSpot(25, 5),
            const FlSpot(30, 4),
          ];
          _currentLoad = 180.2; // TODO: Sum actual usage from history

          // 4. LSTM Forecast
          // TODO: Parse the 24h forecast array from Python API
          _forecastData = [
            const FlSpot(0, 2), const FlSpot(4, 3), const FlSpot(8, 5),
            const FlSpot(12, 6), const FlSpot(16, 5.5), const FlSpot(20, 4),
            const FlSpot(24, 3),
          ];
          _predictedLoad = 245.5; // TODO: Calculate total from forecast data

          // ===================================================================
          // END MOCK DATA
          // ===================================================================

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
      backgroundColor: _bgDark,
      appBar: AppBar(
        title: Text("Energy Analysis", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)), 
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textPrimary),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _cCyan))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMonthSelector(),
                  const SizedBox(height: 24),

                  _buildSectionTitle("Consumption Trend"),
                  const SizedBox(height: 12),
                  _buildTrendChartCard(),
                  const SizedBox(height: 24),

                  _buildSectionTitle("Usage Breakdown"),
                  const SizedBox(height: 12),
                  _buildBreakdownCard(),
                  const SizedBox(height: 24),

                  _buildSectionTitle("Forecast"),
                  const SizedBox(height: 12),
                  _buildForecastingCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI BUILDER METHODS
  // ---------------------------------------------------------------------------

  /// Helper to create consistent section headers.
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textPrimary),
    );
  }

  /// Builds the top navigation bar for selecting months.
  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
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
            onPressed: _selectedDate.month == DateTime.now().month ? null : () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  /// Builds the main line chart showing historical consumption.
  Widget _buildTrendChartCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
      color: _cardDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Total Usage", style: TextStyle(color: _textSecondary, fontSize: 12)),
                    // TODO: Replace with dynamic calculation if needed
                    Text("${_currentLoad.toStringAsFixed(1)} kWh", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textPrimary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    children: [
                      // TODO: Calculate real percentage difference vs last month
                      Icon(Icons.arrow_upward, size: 12, color: Colors.redAccent),
                      SizedBox(width: 4),
                      Text("12% vs last month", style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: _weeklyHistory.isEmpty
                  ? _buildEmptyState("No history data")
                  : LineChart(_mainLineData(_weeklyHistory, _cCyan)),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the pie chart showing CMOEA appliance breakdown.
  Widget _buildBreakdownCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
      color: _cardDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_applianceData.isEmpty)
              _buildEmptyState("No disaggregation data")
            else
              Row(
                children: [
                  SizedBox(
                    height: 120,
                    width: 120,
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
                        centerSpaceRadius: 30,
                        sections: _showingSections(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _applianceData.map((data) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: _buildLegendItem(
                            data['color'], 
                            data['name'], 
                            "${data['value'].toInt()}%"
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
                _analysisTip, // Using dynamic variable
                style: TextStyle(fontSize: 12, color: _textSecondary, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the gradient card for LSTM energy predictions.
  Widget _buildForecastingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF311B92), const Color(0xFF4527A0).withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.auto_graph, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text("Next 24h Projection", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Predicted Total", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                  const SizedBox(height: 4),
                  Text("$_predictedLoad kWh", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: _forecastData.isEmpty
              ? _buildEmptyState("No forecast data")
              : LineChart(_mainLineData(_forecastData, _cPurple, isDarkBg: true)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS & CHART CONFIG
  // ---------------------------------------------------------------------------

  /// Builds a single row in the legend.
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

  /// Displays a message when data lists are empty.
  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message, style: TextStyle(color: _textSecondary, fontSize: 12)),
      ),
    );
  }

  /// Generates the data sections for the Pie Chart.
  List<PieChartSectionData> _showingSections() {
    return List.generate(_applianceData.length, (i) {
      final isTouched = i == _touchedIndex;
      final radius = isTouched ? 40.0 : 30.0; 
      final data = _applianceData[i];

      return PieChartSectionData(
        color: data['color'],
        value: data['value'],
        showTitle: false, 
        radius: radius,
        borderSide: BorderSide(color: _cardDark, width: 2), 
      );
    });
  }

  /// Configures the Line Chart appearance and data.
  LineChartData _mainLineData(List<FlSpot> spots, Color color, {bool isDarkBg = false}) {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withValues(alpha: 0.05), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
               if (value % 5 == 0 && value < spots.last.x) {
                 return Text(
                   value.toInt().toString(), 
                   style: TextStyle(color: _textSecondary, fontSize: 10)
                 );
               }
               return const SizedBox.shrink();
            },
            interval: 1,
            reservedSize: 20,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: spots.first.x,
      maxX: spots.last.x,
      minY: 0,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: color.withValues(alpha: isDarkBg ? 0.3 : 0.1),
          ),
        ),
      ],
    );
  }
}