import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmeter/config/theme.dart';
import 'package:smartmeter/controllers/provider.dart';

class EnergyGoalCard extends StatelessWidget {
  final String title;
  final bool isEditable;
  final bool showHeader;

  const EnergyGoalCard({
    super.key,
    this.title = "Monthly Budget",
    this.isEditable = true,
    this.showHeader = true,
  });

  // Dialogs
  void _showSetGoalDialog(BuildContext context) {
    final provider = context.read<GoalProvider>();
    final controller = TextEditingController(text: provider.target.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Set $title"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Target (kWh)",
            border: OutlineInputBorder(),
            suffixText: "kWh",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) {
                provider.setGoal(val);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.ecoTeal),
            child: const Text("Save"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // State Management
    final goalProvider = context.watch<GoalProvider>();
    
    // Data
    final double goalKwh = goalProvider.target;
    final double usedKwh = goalProvider.current;
    final double progress = goalProvider.progress;
    final bool isOver = goalProvider.isOverBudget;
    final bool isWarning = progress > 0.75;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          if (showHeader) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(title, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                      // --- NEW: NOTIFICATION SYSTEM ---
                      if (isOver || isWarning) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.notifications_active, 
                          size: 18, 
                          color: isOver ? Colors.red : Colors.orange
                        ),
                      ]
                    ],
                  ),
                ),
                if (isEditable)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                    onPressed: () => _showSetGoalDialog(context),
                    tooltip: "Edit $title",
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(left: 8),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Progress Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  "${(progress * 100).toStringAsFixed(0)}%",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOver ? Colors.red : AppTheme.ecoTeal
                  )
              ),
            ],
          ),
          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                  isOver ? Colors.redAccent : AppTheme.ecoTeal
              ),
            ),
          ),

          const SizedBox(height: 12),
          
          // Statistics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${usedKwh.toStringAsFixed(1)} kWh used",
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              Text(
                goalKwh == 0 ? "Set a goal" : "Goal: ${goalKwh.toStringAsFixed(0)} kWh",
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),

          // Alerts
          if (isWarning || isOver) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: (isOver ? Colors.red : Colors.orange).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)
              ),
              child: Row(
                children: [
                  Icon(
                      isOver ? Icons.error_outline : Icons.warning_amber_rounded,
                      size: 20,
                      color: isOver ? Colors.red : Colors.orange
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            isOver ? "Limit Exceeded" : "Warning",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12, 
                              color: isOver ? Colors.red : Colors.orange
                            )
                        ),
                        Text(
                            // CHANGED: Removed "Campus" to be generic for everyone
                            isOver 
                              ? "Usage limit exceeded! Reduce consumption." 
                              : "You are nearing the monthly energy limit.",
                            style: TextStyle(fontSize: 12, color: isOver ? Colors.red : Colors.orange)
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ]
        ],
      ),
    );
  }
}