import 'dart:async';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:multicast_dns/multicast_dns.dart';

class NetworkStateDetector {
  final NetworkInfo _networkInfo = NetworkInfo();
  final String _serviceType = '_smartmeter._tcp.local';

  Future<Map<String, double?>> evaluateApplianceNetworkStates(List<String> registeredAppliances) async {
    // High-level: Replaces hardcoded IP targets with dynamic mDNS local subnet resolution.
    Map<String, double?> states = { for (var item in registeredAppliances) item: null };

    try {
      String? localIP = await _networkInfo.getWifiIP();
      if (localIP == null) {
        return _applyNullFallback(states);
      }

      final MDnsClient client = MDnsClient();
      await client.start();

      await for (PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceType), timeout: const Duration(seconds: 2))) {
        
        await for (SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
          
          String applianceName = ptr.domainName.split('.').first;
          
          for (String registeredName in states.keys) {
            if (applianceName.toLowerCase() == registeredName.toLowerCase()) {
              states[registeredName] = 1.0;
            }
          }
        }
      }
      client.stop();

      // Developer Expectation: Devices failing to respond to mDNS resolution are mathematically mapped offline.
      for (String key in states.keys) {
        if (states[key] == null) {
          states[key] = 0.0;
        }
      }
      
    } catch (_) {
      return _applyNullFallback(states);
    }
    
    return states;
  }

  Map<String, double?> _applyNullFallback(Map<String, double?> stateMatrix) {
    for (String key in stateMatrix.keys) {
      stateMatrix[key] = null;
    }
    return stateMatrix;
  }
}