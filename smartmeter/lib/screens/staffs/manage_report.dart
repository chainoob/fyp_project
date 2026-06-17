// smartmeter/lib/screens/staffs/manage_report.dart

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/config/theme.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/models/app_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

class StaffReportsPage extends StatefulWidget {
  const StaffReportsPage({super.key});

  @override
  State<StaffReportsPage> createState() => _StaffReportsPageState();
}

class _StaffReportsPageState extends State<StaffReportsPage> {
  String _selectedScope = 'Campus';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  String? _selectedBlockId;
  String? _selectedUnitId;
  final TextEditingController _billController = TextEditingController();

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

  @override
  void dispose() {
    _billController.dispose();
    super.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color scaffoldBg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F6F9);
    final Color cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textPrimary = isDark ? Colors.white : Colors.black87;
    final Color inputFill = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03);
    final Color borderSideColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderSideColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Report Parameters", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary)),
                const SizedBox(height: 20),

                DropdownButtonFormField<String>(
                  initialValue: _selectedScope,
                  decoration: _inputDecor("Report Scope", Icons.radar, inputFill, borderSideColor),
                  dropdownColor: cardBg,
                  style: TextStyle(color: textPrimary),
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

                if (_selectedScope != 'Campus')
                  DropdownButtonFormField<String>(
                    initialValue: _selectedBlockId,
                    decoration: _inputDecor(
                      _selectedUnitId != null ? "Block (Locked)" : "Select Block", 
                      Icons.apartment,
                      inputFill,
                      borderSideColor
                    ),
                    dropdownColor: cardBg,
                    style: TextStyle(color: _selectedUnitId != null ? Colors.grey : textPrimary),
                    items: reportProvider.blocks.map((b) => DropdownMenuItem(
                      value: b['id'] as String,
                      child: Text(b['name']),
                    )).toList(),
                    onChanged: _selectedUnitId != null ? null : (val) {
                      setState(() {
                        _selectedBlockId = val;
                        _selectedUnitId = null;
                      });
                      if (val != null) {
                        reportProvider.loadUnitsForBlock(val);
                      }
                    },
                  ),

                if (_selectedScope == 'Unit' && _selectedBlockId != null) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedUnitId,
                    decoration: _inputDecor("Select Unit", Icons.holiday_village, inputFill, borderSideColor),
                    dropdownColor: cardBg,
                    style: TextStyle(color: textPrimary),
                    items: reportProvider.units.map((u) => DropdownMenuItem(
                      value: u['id'] as String,
                      child: Text(u['name']),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedUnitId = val),
                  ),
                ],

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedMonth,
                        decoration: _inputDecor("Month", Icons.calendar_month, inputFill, borderSideColor),
                        dropdownColor: cardBg,
                        style: TextStyle(color: textPrimary),
                        items: _months.map((m) => DropdownMenuItem(value: m, child: Text(_getMonthName(m)))).toList(),
                        onChanged: (val) => setState(() => _selectedMonth = val!),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedYear,
                        decoration: _inputDecor("Year", Icons.calendar_today, inputFill, borderSideColor),
                        dropdownColor: cardBg,
                        style: TextStyle(color: textPrimary),
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
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(child: Text("No reports yet.", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26))),
          )
        ],
      ),
    );
  }

  InputDecoration _inputDecor(String label, IconData icon, Color fill, Color borderSideColor) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: fill,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderSideColor),
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
    // UNIFIED CALCULATION: Cost derived once at the top of the build scope.
    final double calculatedCost = ReportSummary.calculateMalaysianTariffA(data.kpis.totalKwh);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textPrimary = isDark ? Colors.white : Colors.black87;
    final Color borderSideColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareReport(context, calculatedCost),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _downloadReport(context, calculatedCost),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader("1.1 Management Summary", textPrimary),
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
                  _buildSummaryRow("Total Cost", "RM ${calculatedCost.toStringAsFixed(2)}"),
                  const Divider(height: 24),
                  const Text("Key Issue:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  Text(data.summary.keyIssue.isEmpty ? "No operational anomalies identified." : data.summary.keyIssue, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  const Text("Recommended Actions:", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ecoTeal)),
                  if (data.summary.recommendations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text("Maintain standard baseline optimization tracking.", style: TextStyle(fontSize: 13, color: Colors.grey)),
                    )
                  else
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

          const SizedBox(height: 24),
          _buildSectionHeader("1.2 Key Performance Indicators (KPIs)", textPrimary),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _buildKpiCard("Total Energy", "${data.kpis.totalKwh.toStringAsFixed(0)} kWh", Icons.flash_on, Colors.blue, cardBg, borderSideColor),
              _buildKpiCard("Daily Average", "${data.kpis.dailyAvgKwh.toStringAsFixed(1)} kWh", Icons.calendar_view_day, Colors.orange, cardBg, borderSideColor),
              _buildKpiCard("Peak Usage", "${data.kpis.peakKwh.toStringAsFixed(1)} kW", Icons.trending_up, Colors.red, cardBg, borderSideColor),
              _buildKpiCard("Total Cost", "RM ${calculatedCost.toStringAsFixed(0)}", Icons.attach_money, Colors.green, cardBg, borderSideColor),
            ],
          ),

          const SizedBox(height: 24),
          _buildSectionHeader("1.3 Energy Usage Overview", textPrimary),
          Container(
            height: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderSideColor),
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

          const SizedBox(height: 24),
          _buildSectionHeader("1.4 Energy Breakdown", textPrimary),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: data.applianceBreakdown.isEmpty 
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("No appliance signature metrics mapped.", style: TextStyle(color: Colors.grey, fontSize: 13))))
                : Column(
                    children: data.applianceBreakdown.entries.map((entry) {
                      final double baselineTotal = data.kpis.totalKwh > 0 ? data.kpis.totalKwh : 1.0;
                      final percent = entry.value / baselineTotal;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(entry.key, style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary)),
                                Text("${(percent * 100).toStringAsFixed(1)}%", style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Stack(
                              children: [
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white12 : Colors.grey[200],
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

          const SizedBox(height: 24),
          _buildSectionHeader("1.5 Peak Usage Analysis (24h)", textPrimary),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderSideColor),
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

          const SizedBox(height: 24),
          _buildSectionHeader("1.6 Cost Impact", textPrimary),
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: cardBg, 
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderSideColor),
            ),
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
                    Text("RM ${calculatedCost.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: textPrimary)),
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

  Widget _buildSectionHeader(String title, Color textPrimary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary)),
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

  Widget _buildKpiCard(String label, String value, IconData icon, Color color, Color cardBg, Color borderSideColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderSideColor),
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

  Future<Uint8List> _generatePdfReport(String title, EnergyReportData data, double calculatedCost) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Title Header with Teal Accent line
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.teal, width: 2),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "SmartMeter Energy Report",
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        title,
                        style: const pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "Scope: $scope",
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        "Generated: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            
            // Section 1: Management Summary
            pw.Text(
              "1.1 Management Summary",
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildPdfSummaryRow("Total Consumption", "${data.summary.totalConsumption.toStringAsFixed(1)} kWh"),
                  _buildPdfSummaryRow("Vs Last Month", "${data.summary.comparisonPercent > 0 ? '+' : ''}${data.summary.comparisonPercent.toStringAsFixed(1)}%"),
                  _buildPdfSummaryRow("Total Cost", "RM ${calculatedCost.toStringAsFixed(2)}"),
                  pw.Divider(color: PdfColors.grey300, thickness: 1),
                  pw.Text(
                    "Key Issue:",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red700,
                    ),
                  ),
                  pw.Text(
                    data.summary.keyIssue.isEmpty ? "No operational anomalies identified." : data.summary.keyIssue,
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    "Recommended Actions:",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.teal700,
                    ),
                  ),
                  if (data.summary.recommendations.isEmpty)
                    pw.Text(
                      "Maintain standard baseline optimization tracking.",
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                    )
                  else
                    ...data.summary.recommendations.map(
                      (r) => pw.Bullet(
                        text: r,
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            
            // Section 2: KPIs
            pw.Text(
              "1.2 Key Performance Indicators (KPIs)",
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(child: _buildPdfKpiBox("Total Energy", "${data.kpis.totalKwh.toStringAsFixed(1)} kWh")),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildPdfKpiBox("Daily Average", "${data.kpis.dailyAvgKwh.toStringAsFixed(1)} kWh")),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildPdfKpiBox("Peak Usage", "${data.kpis.peakKwh.toStringAsFixed(1)} kW")),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _buildPdfKpiBox("Total Cost", "RM ${calculatedCost.toStringAsFixed(2)}")),
              ],
            ),
            pw.SizedBox(height: 20),
            
            // Section 3: Energy Breakdown
            pw.Text(
              "1.3 Appliance Energy Breakdown",
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal,
              ),
            ),
            pw.SizedBox(height: 8),
            if (data.applianceBreakdown.isEmpty)
              pw.Text("No appliance signature metrics mapped.", style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600))
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
                headers: ["Appliance", "Consumption (kWh)", "Percentage"],
                data: data.applianceBreakdown.entries.map((entry) {
                  final double baselineTotal = data.kpis.totalKwh > 0 ? data.kpis.totalKwh : 1.0;
                  final double percent = entry.value / baselineTotal;
                  return [
                    entry.key,
                    "${entry.value.toStringAsFixed(1)} kWh",
                    "${(percent * 100).toStringAsFixed(1)}%",
                  ];
                }).toList(),
              ),
              
            pw.SizedBox(height: 20),
            // Footer
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                "Generated by SmartMeter System",
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
              ),
            ),
          ];
        },
      ),
    );
    
    return pdf.save();
  }

  pw.Widget _buildPdfSummaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfKpiBox(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
        ],
      ),
    );
  }

  Future<void> _shareReport(BuildContext context, double calculatedCost) async {
    try {
      final pdfBytes = await _generatePdfReport(title, data, calculatedCost);
      final filename = "${title.replaceAll(' ', '_')}.pdf";
      await Printing.sharePdf(bytes: pdfBytes, filename: filename);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to share report: $e")),
        );
      }
    }
  }

  Future<void> _downloadReport(BuildContext context, double calculatedCost) async {
    try {
      final pdfBytes = await _generatePdfReport(title, data, calculatedCost);
      final filename = "${title.replaceAll(' ', '_')}.pdf";
      
      Directory? directory;
      if (Platform.isAndroid || Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }
      
      final filePath = "${directory.path}/$filename";
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Report saved to $filePath"),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: "OPEN",
              onPressed: () async {
                await Printing.layoutPdf(
                  onLayout: (PdfPageFormat format) async => pdfBytes,
                  name: title,
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to download report: $e")),
        );
      }
    }
  }
}

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

    final double rawMax = data.reduce(max);
    final double maxVal = rawMax > 0 ? rawMax * 1.1 : 1.0; 
    
    final double barWidth = (size.width / data.length) * 0.6;
    final double spacing = (size.width / data.length) * 0.4;
    
    final Paint paint = Paint()..style = PaintingStyle.fill;
    
    final Paint gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), gridPaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), gridPaint);

    for (int i = 0; i < data.length; i++) {
      final double val = data[i];
      final double barHeight = (val / maxVal) * size.height;
      final double left = i * (barWidth + spacing);
      final double top = size.height - barHeight;

      paint.color = val > threshold ? accentColor : barColor;

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
    
    final double rawMax = data.reduce(max);
    // Zero-value protection guard
    final double maxVal = rawMax > 0 ? rawMax * 1.2 : 1.0;
    final double stepX = size.width / (data.length - 1);
    
    final path = Path();
    final fillPath = Path();
    
    path.moveTo(0, size.height - (data[0] / maxVal) * size.height);
    fillPath.moveTo(0, size.height); 
    fillPath.lineTo(0, size.height - (data[0] / maxVal) * size.height);

    for (int i = 1; i < data.length; i++) {
      final double x = i * stepX;
      final double y = size.height - (data[i] / maxVal) * size.height;
      
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (int i = 0; i < data.length; i++) {
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