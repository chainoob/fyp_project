import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> location;
  final Map<String, dynamic> metrics;

  UserModel({
    required this.uid,
    required this.profile,
    required this.location,
    required this.metrics,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(doc.data() as Map? ?? {});
    return UserModel(
      uid: doc.id,
      profile: data['profile'] is Map ? Map<String, dynamic>.from(data['profile'] as Map) : const <String, dynamic>{},
      location: data['location'] is Map ? Map<String, dynamic>.from(data['location'] as Map) : const <String, dynamic>{},
      metrics: data['metrics'] is Map ? Map<String, dynamic>.from(data['metrics'] as Map) : const <String, dynamic>{},
    );
  }

  // Legacy Getters to Restore Shell Routing and UI Binding
  String get role => profile['role']?.toString().toLowerCase() ?? 'student';
  String get name => profile['name']?.toString() ?? 'Unknown User';
  String get campusId => location['campus_id']?.toString() ?? '';
  String get blockId => location['block_id']?.toString() ?? '';
  String get unitId => location['unit_id']?.toString() ?? '';
}
