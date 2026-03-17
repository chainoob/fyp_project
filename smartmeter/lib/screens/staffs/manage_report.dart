import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/config/theme.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/models/app_model.dart';

// =============================================================================
// 1. REPORT CONFIGURATION PAGE
// =============================================================================

class StaffReportsPage extends StatefulWidget {
  const StaffReportsPage({super.key});

  @override
  State<StaffReportsPage> createState() => _StaffReportsPageState();
}

class _StaffReportsPageState extends State<StaffReportsPage> {
  // --- UI SELECTION STATE ---
  String _selectedScope = 'Campus';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // Selection Objects
  String? _selectedBlockId;
  String? _selectedUnitId;

  final List<String> _scopes = ['Campus', 'Block', 'Unit'];
  final List<int> _months = List.generate(12, (index) => index + 1);
  final List<int> _years = List.generate(5, (index) => DateTime.now().year - index);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportProvider>().loadInitialData();
    });
  }

  Future<void> _handleGenerateReport() async {
    final provider = context.read<ReportProvider>();

    try {
      final reportData = await provider.generateReport(
        scope: _selectedScope,
        month: _selectedMonth,
        year: _selectedYear,
        blockId: _selectedBlockId,
        unitId: _selectedUnitId,
      );

      if (reportData != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GeneratedReportScreen(
              data: reportData,
              scope: _selectedScope,
              title: "${_getMonthName(_selectedMonth)} $_selectedYear Report",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to generate: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportProvider = context.watch<ReportProvider>();
    final isLoading = reportProvider.isLoading;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // CONFIGURATION CARD
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Report Parameters", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 20),

                // Scope
                DropdownButtonFormField<String>(
                  initialValue: _selectedScope,
                  decoration: _inputDecor("Report Scope", Icons.radar),
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: Colors.white),
                  items: _scopes.map((s) => DropdownMenuItem(value: s, child: Text("$s Level"))).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedScope = val!;
                      _selectedBlockId = null;
                      _selectedUnitId = null;
                      reportProvider.clearUnits();
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Block Selector
                if (_selectedScope != 'Campus')
                  DropdownButtonFormField<String>(
                    initialValue: _selectedBlockId,
                    decoration: _inputDecor("Select Block", Icons.apartment),
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: Colors.white),
                    items: reportProvider.blocks.map((b) => DropdownMenuItem(
                      value: b['id'] as String,
                      child: Text(b['name']),
                    )).toList(),
                    onChanged: (val) {
                      setState(() => _selectedBlockId = val);
                      if (val != null) {
                        reportProvider.loadUnitsForBlock(val);
                      }
                    },
                  ),

                // Unit Selector
                if (_selectedScope == 'Unit' && _selectedBlockId != null) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedUnitId,
                    decoration: _inputDecor("Select Unit", Icons.holiday_village),
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: Colors.white),
                    items: reportProvider.units.map((u) => DropdownMenuItem(
                      value: u['id'] as String,
                      child: Text(u['name']),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedUnitId = val),
                  ),
                ],

                const SizedBox(height: 16),

                // Date Selectors
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedMonth,
                        decoration: _inputDecor("Month", Icons.calendar_month),
                        dropdownColor: AppTheme.surface,
                        style: const TextStyle(color: Colors.white),
                        items: _months.map((m) => DropdownMenuItem(value: m, child: Text(_getMonthName(m)))).toList(),
                        onChanged: (val) => setState(() => _selectedMonth = val!),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedYear,
                        decoration: _inputDecor("Year", Icons.calendar_today),
                        dropdownColor: AppTheme.surface,
                        style: const TextStyle(color: Colors.white),
                        items: _years.map((y) => DropdownMenuItem(value: y, child: Text("$y"))).toList(),
                        onChanged: (val) => setState(() => _selectedYear = val!),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isLoading ? null : _handleGenerateReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.ecoTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.analytics),
                    label: Text(isLoading ? "GENERATING..." : "GENERATE REPORT", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text("Recent Reports", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(child: Text("No reports yet.", style: TextStyle(color: Colors.white24))),
          )
        ],
      ),
    );
  }

  InputDecoration _inputDecor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppTheme.ecoTeal),
      ),
    );
  }

  String _getMonthName(int month) {
    const names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return names[month - 1];
  }
}

// =============================================================================
// 2. GENERATED REPORT SCREEN
// =============================================================================

class GeneratedReportScreen extends StatelessWidget {
  final EnergyReportData data;
  final String scope;
  final String title;

  const GeneratedReportScreen({
    super.key,
    required this.data,
    required this.scope,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: () {}),
          IconButton(icon: const Icon(Icons.download), onPressed: () {}),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- 1.1 MANAGEMENT SUMMARY ---
          _buildSectionHeader("1.1 Management Summary"),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryRow("Total Consumption", "${data.summary.totalConsumption.toStringAsFixed(0)} kWh"),
                  _buildSummaryRow("Vs Last Month", "${data.summary.comparisonPercent > 0 ? '+' : ''}${data.summary.comparisonPercent.toStringAsFixed(1)}%", isTrend: true),
                  _buildSummaryRow("Total Cost", "RM ${data.summary.totalCost.toStringAsFixed(2)}"),
                  const Divider(height: 24),
                  const Text("Key Issue:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  Text(data.summary.keyIssue, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  const Text("Recommended Actions:", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ecoTeal)),
                  ...data.summary.recommendations.map((r) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Text(r, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ),

          // --- 1.2 KEY PERFORMANCE INDICATORS ---
          const SizedBox(height: 24),
          _buildSectionHeader("1.2 Key Performance Indicators (KPIs)"),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _buildKpiCard("Total Energy", "${data.kpis.totalKwh.toStringAsFixed(0)} kWh", Icons.flash_on, Colors.blue),
              _buildKpiCard("Daily Average", "${data.kpis.dailyAvgKwh.toStringAsFixed(1)} kWh", Icons.calendar_view_day, Colors.orange),
              _buildKpiCard("Peak Usage", "${data.kpis.peakKwh.toStringAsFixed(1)} kW", Icons.trending_up, Colors.red),
              _buildKpiCard("Total Cost", "RM ${data.kpis.totalCost.toStringAsFixed(0)}", Icons.attach_money, Colors.green),
            ],
          ),

          // --- 1.3 ENERGY USAGE OVERVIEW (IMPROVED BAR CHART) ---
          const SizedBox(height: 24),
          _buildSectionHeader("1.3 Energy Usage Overview"),
          Container(
            height: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: BarChartPainter(
                      data: data.usageTrend.map((e) => e.value).toList(),
                      labels: data.usageTrend.map((e) => e.day.toString()).toList(),
                      barColor: AppTheme.ecoTeal,
                      accentColor: Colors.redAccent,
                      threshold: data.kpis.dailyAvgKwh * 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text("Daily Consumption (30 Days)", style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),

          // --- 1.4 ENERGY BREAKDOWN ---
          const SizedBox(height: 24),
          _buildSectionHeader("1.4 Energy Breakdown"),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: data.applianceBreakdown.entries.map((entry) {
                  final percent = entry.value / data.kpis.totalKwh;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text("${(percent * 100).toStringAsFixed(1)}%", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: percent.clamp(0.0, 1.0),
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _getColorForAppliance(entry.key),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text("${entry.value.toStringAsFixed(1)} kWh", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // --- 1.5 PEAK USAGE & HOURLY ANALYSIS (IMPROVED LINE CHART) ---
          const SizedBox(height: 24),
          _buildSectionHeader("1.5 Peak Usage Analysis (24h)"),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: LineChartPainter(
                      data: List.generate(24, (i) => data.hourlyUsage[i] ?? 0.0),
                      lineColor: Colors.orange,
                      fillColor: Colors.orange.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text("12 AM", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text("6 AM", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text("12 PM", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text("6 PM", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text("11 PM", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                )
              ],
            ),
          ),

          // --- 1.6 COST IMPACT ---
          const SizedBox(height: 24),
          _buildSectionHeader("1.6 Cost Impact"),
          Container(
            height: 100,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.monetization_on, color: Colors.green, size: 32),
                const SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("RM ${data.kpis.totalCost.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
                    const Text("Estimated Monthly Cost", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
          const Center(child: Text("Generated by SmartMeter System", style: TextStyle(color: Colors.grey, fontSize: 10))),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTrend = false}) {
    Color? valColor;
    if (isTrend) {
      valColor = value.startsWith('+') ? Colors.red : Colors.green;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: valColor)),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  Color _getColorForAppliance(String name) {
    switch (name) {
      case 'Fan': return Colors.blue;
      case 'Laptop': return Colors.purple;
      case 'Charger': return Colors.green;
      case 'Lamp': return Colors.amber;
      case 'Iron': return Colors.redAccent;
      case 'Kettle': return Colors.orange;
      case 'Printer': return Colors.indigo;
      default: return Colors.grey;
    }
  }
}

// =============================================================================
// 3. CUSTOM PAINTERS (FOR CHARTING)
// =============================================================================

class BarChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color barColor;
  final Color accentColor;
  final double threshold;

  BarChartPainter({
    required this.data,
    required this.labels,
    required this.barColor,
    required this.accentColor,
    required this.threshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double maxVal = data.reduce(max) * 1.1; // Add 10% headroom
    final double barWidth = (size.width / data.length) * 0.6;
    final double spacing = (size.width / data.length) * 0.4;
    
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), gridPaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), gridPaint);

    for (int i = 0; i < data.length; i++) {
      final double val = data[i];
      final double barHeight = (val / maxVal) * size.height;
      final double left = i * (barWidth + spacing);
      final double top = size.height - barHeight;

      // Color logic: High usage gets accent color
      paint.color = val > threshold ? accentColor : barColor;

      // Draw rounded rect bar
      final RRect bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(bar, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color fillColor;

  LineChartPainter({
    required this.data,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final double maxVal = data.reduce(max) * 1.2;
    final double stepX = size.width / (data.length - 1);
    
    final path = Path();
    final fillPath = Path();
    
    // Start path
    path.moveTo(0, size.height - (data[0] / maxVal) * size.height);
    fillPath.moveTo(0, size.height); // Bottom left
    fillPath.lineTo(0, size.height - (data[0] / maxVal) * size.height);

    for (int i = 1; i < data.length; i++) {
      final double x = i * stepX;
      final double y = size.height - (data[i] / maxVal) * size.height;
      
      // Simple straight line connection (for hourly data, curves can be misleading if not interpolated perfectly)
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    // Close fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Draw Fill
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw Line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Draw Dots
    final dotPaint = Paint()..color = lineColor;
    for (int i = 0; i < data.length; i++) {
      // Only draw dots for key hours (every 6 hours) to reduce clutter
      if (i % 6 == 0) {
        final double x = i * stepX;
        final double y = size.height - (data[i] / maxVal) * size.height;
        canvas.drawCircle(Offset(x, y), 3, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}