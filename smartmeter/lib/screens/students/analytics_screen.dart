import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/controllers/provider.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _touchedIndex = -1; 
  DateTime _selectedDate = DateTime.now();

  final Color _bgDark = const Color(0xFF121212);      
  final Color _cardDark = const Color(0xFF1E1E1E);    
  final Color _textPrimary = Colors.white;            
  final Color _textSecondary = Colors.white54;        
  final Color _cCyan = const Color(0xFF00E5FF);         

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRealData();
    });
  }

  void _loadRealData() {
    final user = context.read<AppAuthProvider>().currentUser;
    if (user != null) {
      context.read<EnergyProvider>().loadReport(
        scope: 'Unit',
        month: _selectedDate.month,
        year: _selectedDate.year,
        unitId: user.uid, 
      );

      // Hook into real-time telemetry hardware listeners via Firestore
      context.read<EnergyProvider>().subscribeToTelemetry(user.uid);
    }
  }
  void _changeMonth(int offset) {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + offset);
    });
    _loadRealData(); 
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EnergyProvider>();

    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        title: Text("Energy Analysis", style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)), 
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textPrimary),
      ),
      body: _buildBody(provider),
    );
  }

  Widget _buildBody(EnergyProvider provider) {
    if (provider.isLoading || provider.isProcessingML) {
      return Center(child: CircularProgressIndicator(color: _cCyan));
    }

    final mlReport = provider.currentMlReport?.data;

    if (mlReport == null) {
      return Column(
        children: [
          _buildMonthSelector(),
          const Expanded(
            child: Center(
              child: Text(
                "No analysis data available for this month.\nAwaiting staff bill submission.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthSelector(),
          const SizedBox(height: 24),

          if (mlReport.anomalies.isNotEmpty) ...[
            _buildAnomaliesCard(mlReport.anomalies),
            const SizedBox(height: 24),
          ],

          _buildSectionTitle("Usage Breakdown"),
          const SizedBox(height: 12),
          _buildBreakdownCard(
            mlReport.estimatedLoad,
            mlReport.breakdown.entries.toList(),
            mlReport.recommendations.isNotEmpty ? mlReport.recommendations.first : "Consumption within typical parameters.",
            mlReport.benchmarkBreakdown,
          ),
          
          const SizedBox(height: 24),
          _buildSectionTitle("24h Load Profile"),
          const SizedBox(height: 12),
          _buildHourlyTrendCard(mlReport.hourlyUsage),
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
            onPressed: _selectedDate.month == DateTime.now().month ? null : () => _changeMonth(1),
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
                      final percentage = (entry.value / totalConsumption) * 100;
                      
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

  Widget _buildHourlyTrendCard(Map<int, double> hourlyData) {
    if (hourlyData.isEmpty) {
      return const SizedBox.shrink();
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
}