import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> getMonthlySummary(String userId, int year, int month) async {
    try {
      final String monthId = "$year-${month.toString().padLeft(2, '0')}";
      final DocumentSnapshot doc = await _db
          .collection('users')
          .doc(userId)
          .collection('billing_cycles')
          .doc(monthId)
          .get();

      if (!doc.exists || doc.data() == null) return null;

      final data = Map<String, dynamic>.from(doc.data() as Map);
      data['document_id'] = doc.id; 
      return data;
    } on FirebaseException catch (e) {
      developer.log('Firestore Read Error: [${e.code}] ${e.message}', name: 'DatabaseService');
      return null;
    } catch (e) {
      developer.log('Unknown Serialization Error: $e', name: 'DatabaseService');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getDailyDisaggregations(String userId, int year, int month) async {
    try {
      final String monthId = "$year-${month.toString().padLeft(2, '0')}";
      final QuerySnapshot query = await _db
          .collection('users')
          .doc(userId)
          .collection('billing_cycles')
          .doc(monthId)
          .collection('daily_disaggregations')
          .orderBy('timestamp', descending: true)
          .get();
      
      return query.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        data['document_id'] = doc.id; 
        return data;
      }).toList();
    } on FirebaseException catch (e) {
      developer.log('Firestore Query Error: [${e.code}] ${e.message}', name: 'DatabaseService');
      return [];
    } catch (e) {
      developer.log('Unknown Serialization Error: $e', name: 'DatabaseService');
      return [];
    }
  }
}