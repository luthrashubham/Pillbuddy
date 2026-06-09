import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'notification_service.dart';

class RemainderScreen extends StatefulWidget {
  final String? reminderId;
  final Map<String, dynamic>? existingData;

  const RemainderScreen({super.key, this.reminderId, this.existingData});

  @override
  _RemainderScreenState createState() => _RemainderScreenState();
}

class _RemainderScreenState extends State<RemainderScreen> {
  List<TimeOfDay> selectedTimes = [];
  bool isSaving = false;

  List<TextEditingController> medicineControllers = [TextEditingController()];
  List<String> _medicineHistory = [];

  final DatabaseReference rtdbRef = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://abhiyantrix-330d6-default-rtdb.asia-southeast1.firebasedatabase.app/',
  ).ref();

  @override
  void initState() {
    super.initState();
    _fetchMedicineHistory();

    if (widget.existingData != null) {
      final meds = widget.existingData!['medicines'] as List<dynamic>? ?? [];
      if (meds.isNotEmpty) {
        medicineControllers = meds
            .map((m) => TextEditingController(text: m.toString()))
            .toList();
      }

      final times = widget.existingData!['times'] as List<dynamic>? ?? [];
      selectedTimes = times.map((t) {
        final parts = t.toString().split(':');
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }).toList();
    }
  }

  @override
  void dispose() {
    for (final controller in medicineControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchMedicineHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('history')
          .get();

      final Set<String> uniqueMedicines = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['BrandName'] as String?;

        if (name != null && name.trim().isNotEmpty) {
          uniqueMedicines.add(name.trim());
        }
      }

      if (mounted) {
        setState(() {
          _medicineHistory = uniqueMedicines.toList();
        });
      }
    } catch (e) {
      print("Error fetching history: $e");
    }
  }

  Future<void> _syncRTDBFromFirestore(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .get();

    List<String> allTimes = [];
    List<String> allMeds = [];

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final times = (data['times'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      final meds = (data['medicines'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      allTimes.addAll(times);
      allMeds.addAll(meds);
    }

    allTimes = allTimes.toSet().toList()
      ..sort((a, b) {
        final aParts = a.split(':');
        final bParts = b.split(':');

        final aMin = int.parse(aParts[0]) * 60 + int.parse(aParts[1]);
        final bMin = int.parse(bParts[0]) * 60 + int.parse(bParts[1]);

        return aMin.compareTo(bMin);
      });

    allMeds = allMeds.toSet().toList();

    await rtdbRef.child('reminders').set({
      "times": allTimes,
      "medicines": allMeds,
    });
  }

  Future<void> pickTime() async {
    TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null && !selectedTimes.contains(time)) {
      setState(() {
        selectedTimes.add(time);
      });
    }
  }

  void addMedicineField() {
    setState(() {
      medicineControllers.add(TextEditingController());
    });
  }

  Future<void> saveReminder() async {
    List<String> meds = medicineControllers
        .map((c) => c.text.trim())
        .where((m) => m.isNotEmpty)
        .toList();

    if (selectedTimes.isEmpty || meds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least one time and one medicine")),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must be logged in to save reminders."),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      List<String> timeStrings = selectedTimes
          .map(
            (t) =>
                "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}",
          )
          .toList();

      final docRef = widget.reminderId != null
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('reminders')
                .doc(widget.reminderId)
          : FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('reminders')
                .doc();

      await docRef.set({
        'medicines': meds,
        'times': timeStrings,
        'createdAt':
            widget.existingData?['createdAt'] ?? FieldValue.serverTimestamp(),
      });

      await _syncRTDBFromFirestore(user.uid);

      int baseId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      for (int i = 0; i < selectedTimes.length; i++) {
        final time = selectedTimes[i];
        final now = DateTime.now();

        var scheduledDate = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );

        if (scheduledDate.isBefore(now)) {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        }

        await NotificationService.scheduleNotification(
          baseId + i,
          scheduledDate,
          "Pill Buddy",
          "Time to take: ${meds.join(", ")}",
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Reminders saved!")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error saving reminder: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.reminderId == null ? "Add Reminder" : "Edit Reminder",
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Alarm Times",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8.0,
              children: selectedTimes.map((time) {
                return Chip(
                  label: Text(time.format(context)),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () {
                    setState(() {
                      selectedTimes.remove(time);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: pickTime,
              icon: const Icon(Icons.add_alarm),
              label: const Text("Add Alarm Time"),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: ListView.builder(
                itemCount: medicineControllers.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return DropdownMenu<String>(
                          width: constraints.maxWidth,
                          controller: medicineControllers[index],
                          label: Text("Medicine ${index + 1}"),
                          hintText: "Select from history or type new",
                          enableFilter: true,
                          requestFocusOnTap: true,
                          dropdownMenuEntries: _medicineHistory
                              .map(
                                (name) => DropdownMenuEntry<String>(
                                  value: name,
                                  label: name,
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Add Medicine"),
                IconButton(
                  icon: const Icon(Icons.add_circle, size: 30),
                  onPressed: addMedicineField,
                ),
              ],
            ),
            const SizedBox(height: 10),
            isSaving
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: saveReminder,
                    child: const Text("Save Reminders"),
                  ),
          ],
        ),
      ),
    );
  }
}