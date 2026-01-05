import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartmeter/config/theme.dart';

// -----------------------------------------------------------------------------
// 1. MANAGE BLOCKS SCREEN (Level 1)
// Schema: blocks/ { name, isActive }
// -----------------------------------------------------------------------------

class ManageBlocksScreen extends StatefulWidget {
  const ManageBlocksScreen({super.key});

  @override
  State<ManageBlocksScreen> createState() => _ManageBlocksScreenState();
}

class _ManageBlocksScreenState extends State<ManageBlocksScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _showBlockDialog({DocumentSnapshot? block}) async {
    final nameController = TextEditingController(text: block?['name'] ?? '');
    bool isActive = block?['isActive'] ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(block == null ? "Add Block" : "Edit Block"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Block Name"),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text("Is Active?"),
                  value: isActive,
                  onChanged: (val) => setState(() => isActive = val),
                  activeThumbColor: AppTheme.ecoTeal,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  try {
                    final data = {
                      'name': nameController.text.trim(),
                      'isActive': isActive,
                      'updatedAt': FieldValue.serverTimestamp(),
                    };

                    if (block == null) {
                      await _db.collection('blocks').add({
                        ...data,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    } else {
                      await block.reference.update(data);
                    }
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if(context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                    }
                  }
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteBlock(DocumentSnapshot block) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Block?"),
        content: Text("Delete '${block['name']}'? This effectively removes access to all units and rooms inside it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text("Delete")),
        ],
      ),
    );
    if (confirm == true) await block.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Blocks")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBlockDialog(),
        icon: const Icon(Icons.add),
        label: const Text("Add Block"),
        backgroundColor: AppTheme.navyBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('blocks').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("No blocks found."));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final block = docs[index];
              final data = block.data() as Map<String, dynamic>;
              final isActive = data['isActive'] ?? true;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive ? AppTheme.navyBlue.withValues(alpha: .1) : Colors.grey.withValues(alpha: 0.1),
                    child: Icon(Icons.apartment, color: isActive ? AppTheme.navyBlue : Colors.grey),
                  ),
                  title: Text(data['name'], style: TextStyle(color: isActive ? null : Colors.grey, fontWeight: FontWeight.bold)),
                  subtitle: Text(isActive ? "Active" : "Inactive", style: TextStyle(color: isActive ? AppTheme.ecoTeal : Colors.grey, fontSize: 12)),
                  trailing: PopupMenuButton(
                    onSelected: (val) => val == 'edit' ? _showBlockDialog(block: block) : _deleteBlock(block),
                    itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text("Edit")), const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.red)))],
                  ),
                  onTap: () => Navigator.push(
                    context, 
                    MaterialPageRoute(
                      builder: (_) => ManageUnitsScreen(blockId: block.id, blockName: data['name'])
                    )
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. MANAGE UNITS SCREEN (Level 2)
// Schema: blocks/{blockId}/units/ { name }
// -----------------------------------------------------------------------------

class ManageUnitsScreen extends StatefulWidget {
  final String blockId;
  final String blockName;

  const ManageUnitsScreen({super.key, required this.blockId, required this.blockName});

  @override
  State<ManageUnitsScreen> createState() => _ManageUnitsScreenState();
}

class _ManageUnitsScreenState extends State<ManageUnitsScreen> {
  CollectionReference get _unitsRef => 
      FirebaseFirestore.instance.collection('blocks').doc(widget.blockId).collection('units');

  Future<void> _showUnitDialog({DocumentSnapshot? unit}) async {
    final nameController = TextEditingController(text: unit?['name'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(unit == null ? "Add Unit" : "Edit Unit"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Unit Name"),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              try {
                if (unit == null) {
                  await _unitsRef.add({
                    'name': nameController.text.trim(),
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } else {
                  await unit.reference.update({'name': nameController.text.trim()});
                }
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUnit(DocumentSnapshot unit) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Unit?"),
        content: Text("Are you sure you want to delete '${unit['name']}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text("Delete")),
        ],
      ),
    );
    if (confirm == true) await unit.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.blockName} > Units")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUnitDialog(),
        icon: const Icon(Icons.add),
        label: const Text("Add Unit"),
        backgroundColor: AppTheme.navyBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _unitsRef.orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.layers_clear_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("No units in this block.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final unit = docs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.1),
                    child: const Icon(Icons.holiday_village, color: AppTheme.navyBlue),
                  ),
                  title: Text(unit['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: PopupMenuButton(
                    onSelected: (val) => val == 'edit' ? _showUnitDialog(unit: unit) : _deleteUnit(unit),
                    itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text("Edit")), const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.red)))],
                  ),
                  onTap: () => Navigator.push(
                    context, 
                    MaterialPageRoute(
                      builder: (_) => ManageRoomsScreen(
                        blockId: widget.blockId, 
                        blockName: widget.blockName,
                        unitId: unit.id,
                        unitName: unit['name'],
                      )
                    )
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. MANAGE ROOMS SCREEN (Level 3)
// Schema: blocks/{blockId}/units/{unitId}/rooms/ { name, capacity, occupant, isOccupied }
// -----------------------------------------------------------------------------

class ManageRoomsScreen extends StatefulWidget {
  final String blockId;
  final String blockName;
  final String unitId;
  final String unitName;

  const ManageRoomsScreen({
    super.key, 
    required this.blockId, 
    required this.blockName,
    required this.unitId,
    required this.unitName
  });

  @override
  State<ManageRoomsScreen> createState() => _ManageRoomsScreenState();
}

class _ManageRoomsScreenState extends State<ManageRoomsScreen> {
  CollectionReference get _roomsRef =>
      FirebaseFirestore.instance
          .collection('blocks').doc(widget.blockId)
          .collection('units').doc(widget.unitId)
          .collection('rooms');

  Future<Map<String, dynamic>?> _showStudentSearchSheet() async {
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => const _StudentSearchSheet(),
    );
  }

  Future<void> _showRoomDialog({DocumentSnapshot? room}) async {
    final nameController = TextEditingController(text: room?['name'] ?? '');
    final capacityController = TextEditingController(text: room?['capacity']?.toString() ?? '1');
    
    Map<String, dynamic>? selectedStudent;
    if (room != null && room['occupant'] != null) {
      selectedStudent = Map<String, dynamic>.from(room['occupant']);
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(room == null ? "Add Room" : "Edit Room"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Room Number"),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: capacityController,
                    decoration: const InputDecoration(labelText: "Capacity"),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),
                  const Align(alignment: Alignment.centerLeft, child: Text("Occupant", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey))),
                  const SizedBox(height: 8),
                  
                  InkWell(
                    onTap: () async {
                      final result = await _showStudentSearchSheet();
                      if (result != null) setState(() => selectedStudent = result);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(selectedStudent == null ? Icons.person_add : Icons.person, color: selectedStudent == null ? Colors.grey : AppTheme.ecoTeal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedStudent == null ? "Assign student..." : "${selectedStudent!['name']}",
                              style: TextStyle(color: selectedStudent == null ? Colors.grey : Colors.white),
                            ),
                          ),
                          if (selectedStudent != null)
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => selectedStudent = null),
                              constraints: const BoxConstraints(),
                            )
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  final roomData = {
                    'name': nameController.text.trim(),
                    'capacity': int.tryParse(capacityController.text) ?? 1,
                    'isOccupied': selectedStudent != null,
                    'occupant': selectedStudent,
                  };

                  try {
                    if (room == null) {
                      await _roomsRef.add({...roomData, 'createdAt': FieldValue.serverTimestamp()});
                    } else {
                      await room.reference.update(roomData);
                    }
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                    }
                  }
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteRoom(DocumentSnapshot room) async {
    await room.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.unitName} Rooms")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRoomDialog(),
        icon: const Icon(Icons.add),
        label: const Text("Add Room"),
        backgroundColor: AppTheme.ecoTeal,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _roomsRef.orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("No rooms added yet."));

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.1),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final room = docs[index];
              final data = room.data() as Map<String, dynamic>;
              final bool isOccupied = data['isOccupied'] ?? false;
              final occupantName = data['occupant']?['name'] ?? "Vacant";

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isOccupied ? AppTheme.ecoTeal.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.2))),
                child: InkWell(
                  onTap: () => _showRoomDialog(room: room),
                  onLongPress: () => _deleteRoom(room),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(Icons.meeting_room, color: isOccupied ? AppTheme.ecoTeal : Colors.grey),
                            if (isOccupied) const Icon(Icons.check_circle, size: 16, color: AppTheme.ecoTeal)
                          ],
                        ),
                        const Spacer(),
                        Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text(occupantName, style: TextStyle(fontSize: 12, color: isOccupied ? Colors.white70 : Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HELPER: STUDENT SEARCH SHEET (Unchanged from optimization)
// -----------------------------------------------------------------------------

class _StudentSearchSheet extends StatefulWidget {
  const _StudentSearchSheet();

  @override
  State<_StudentSearchSheet> createState() => _StudentSearchSheetState();
}

class _StudentSearchSheetState extends State<_StudentSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.length >= 2) {
        _performSearch(query);
      } else {
        setState(() => _results = []);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('displayName', isGreaterThanOrEqualTo: query)
          .where('displayName', isLessThan: '$query\uf8ff')
          .limit(10)
          .get();

      final results = snapshot.docs.map((doc) => {
        'uid': doc.id,
        'name': doc['displayName'] ?? 'Unknown',
        'email': doc['email'] ?? '',
      }).toList();

      if (mounted) setState(() => _results = results);
    } catch (e) {
      // Handle error
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          const Text("Assign Student", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isLoading ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _results.isEmpty 
              ? const Center(child: Text("No results found", style: TextStyle(color: Colors.grey))) 
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final student = _results[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(student['name']),
                      subtitle: Text(student['email']),
                      onTap: () => Navigator.pop(context, student),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}