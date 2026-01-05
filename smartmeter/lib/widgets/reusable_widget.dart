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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
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