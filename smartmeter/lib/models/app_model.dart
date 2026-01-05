import 'package:cloud_firestore/cloud_firestore.dart';

// --- USER MODEL ---
class Users {
  final String uid;
  final String name;
  final String email;
  final String role; // 'student' or 'staff'
  final String? studentId;
  final String? dormBlock;
  final String? department;
  final String? photoUrl;

  const Users({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.studentId,
    this.dormBlock,
    this.department,
    this.photoUrl
  });

  factory Users.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Users(
      uid: doc.id,
      name: data['displayName'] ?? 'Unknown',
      email: data['email'] ?? '',
      role: data['role'] ?? 'student',
      studentId: data['studentId'],
      dormBlock: data['dormBlock'],
      department: data['department'],
      photoUrl: data['photoUrl']
    );
  }
}

// --- APPLIANCE MODEL ---
class Appliance {
  final String id;
  final String ownerId;
  final String name;
  final String type;
  final int wattage;
  final String status;
  final String? room;
  final DateTime? verificationDate;

  const Appliance({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    required this.wattage,
    this.status = 'pending',
    this.room,
    this.verificationDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'ownerId':ownerId,
      'name': name,
      'type': type,
      'wattage': wattage,
      'status': status,
      'room': room,
      'verificationDate': verificationDate,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory Appliance.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    String resolvedOwnerId = data['ownerId'] ?? '';
    if (resolvedOwnerId.isEmpty && doc.reference.parent.parent != null) {
      resolvedOwnerId = doc.reference.parent.parent!.id;
    }

    return Appliance(
      id: doc.id,
      ownerId: resolvedOwnerId, // <--- LOAD THIS
      name: data['name'] ?? 'Unknown Device',
      type: data['type'] ?? 'other',
      wattage: data['wattage'] ?? 0,
      status: data['status'] ?? 'pending',
      room: data['room'],
      verificationDate: (data['verificationDate'] as Timestamp?)?.toDate(),
    );
  }
}