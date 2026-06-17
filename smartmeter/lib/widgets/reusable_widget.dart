import 'package:flutter/material.dart';
import 'package:smartmeter/config/theme.dart';
import 'package:smartmeter/models/app_model.dart';

class MetricTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const MetricTile({required this.label, required this.value, required this.icon, required this.color, super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class ApplianceCard extends StatelessWidget {
  final Appliance app;
  const ApplianceCard({required this.app, super.key});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    
    switch (app.status) {
      case 'active': statusColor = AppTheme.ecoTeal; statusIcon = Icons.check_circle; break;
      case 'rejected': statusColor = Colors.red; statusIcon = Icons.cancel; break;
      default: statusColor = Colors.amber; statusIcon = Icons.hourglass_empty;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: statusColor.withValues(alpha: 0.1), child: Icon(Icons.power, color: statusColor)),
        title: Text(app.name),
        subtitle: Text("${app.wattage}W • ${app.status.toUpperCase()}"),
        trailing: Icon(statusIcon, color: statusColor, size: 20),
      ),
    );
  }
}

class AppAlertDialog extends StatelessWidget {
  final String title;
  final String content;
  final List<Widget> actions;

  const AppAlertDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
      content: Text(content, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
      actions: actions,
    );
  }
}