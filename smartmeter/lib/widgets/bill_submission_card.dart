import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/provider.dart';

class BillSubmissionCard extends StatefulWidget {
  final String userId;
  final String blockId;
  final String? telemetrySourceId;
  final int? month;
  final int? year;

  const BillSubmissionCard({
    super.key, 
    required this.userId, 
    required this.blockId,
    this.telemetrySourceId,
    this.month,
    this.year,
  });

  @override
  State<BillSubmissionCard> createState() => _BillSubmissionCardState();
}

class _BillSubmissionCardState extends State<BillSubmissionCard> {
  final TextEditingController _billController = TextEditingController();

  @override
  void dispose() {
    _billController.dispose();
    super.dispose();
  }

  void _submitBill() async {
    final double? billTotal = double.tryParse(_billController.text);
    if (billTotal == null || billTotal <= 0) return;

    FocusScope.of(context).unfocus();
    
    try {
      await context.read<EnergyProvider>().runDisaggregation(
        widget.userId,
        DateTime.now().millisecondsSinceEpoch.toString(), 
        billTotal,
        scope: 'Unit',
        month: widget.month ?? DateTime.now().month,
        year: widget.year ?? DateTime.now().year,
        telemetrySourceId: widget.telemetrySourceId,
        blockId: widget.blockId,
      );

      if (mounted) {
        _billController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("AI Analysis Complete. Data broadcasted to students."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Submission Failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing = context.watch<EnergyProvider>().isProcessingAI;

    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Submit Monthly Bill", 
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _billController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Enter total kWh",
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8), 
                        borderSide: BorderSide.none
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isProcessing ? null : _submitBill,
                  child: isProcessing 
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                        )
                      : const Text("Analyze", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}